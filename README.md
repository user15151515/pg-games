# pg games

Juegos cortos multijugador para jugar con amigos. Web estática, sin registro: se juega compartiendo un enlace.

Juegos: Pistas (`pistas/`), por parejas o equipos de hasta cuatro: uno da pistas de una o dos palabras por chat y el resto adivina una palabra por cada letra de una lista, contra el reloj. La palabra secreta solo la reciben quien da pistas y los otros equipos (por el canal privado de cada uno, no en el estado común); el anfitrión rechaza pistas que contengan la palabra o se le parezcan. Puntos: 10 por palabra con una pista, uno menos por cada pista extra (mínimo 3) y un punto por segundo sobrante si se completan todas las letras; con una sola pareja hay récord en el navegador del anfitrión. Teclazo (`teclazo/`), carrera de mecanografía en la que cada coche avanza según lo que escribes; se juega en sala o en individual contra la sombra de tu récord (ppm y precisión, guardados en el navegador). Tutti frutti (`tutti/`), una letra al azar y varias categorías que se pueden personalizar; se puntúa por respuestas únicas y los jugadores pueden votar las que no valen. Tiene modo individual contra el reloj, en el que el propio jugador corrige sus respuestas, con récord guardado en el navegador por combinación de rondas, tiempo y categorías. Bomba (`bomba/`), una sílaba, una palabra, pasa la bomba. Con ajustes de vidas, dificultad, tipo y duración de la mecha, orden de pase (círculo, rebote o azar) y más; las reglas están explicadas dentro del juego, en «Cómo se juega». Tiene modo individual (aciertos, racha y récord, guardado en el navegador por combinación de ajustes), salir de la sala en cualquier momento y expulsión de jugadores por parte del anfitrión.

## Multijugador

Los mensajes pasan por Supabase Realtime (solo broadcast: sin tablas ni base de datos) en un proyecto propio de pg games, independiente de cualquier otro. Quien crea la sala es el anfitrión y lleva la partida (turnos, mecha, validación de palabras); los demás le envían sus acciones. Hay un canal común por sala (lo que emite el anfitrión) y un canal por invitado (lo que se dicen ese invitado y el anfitrión), así que cada mensaje de un invitado lo recibe solo el anfitrión. Al crear sala se comprueba que el código esté libre, hay un tope de 40 mensajes por segundo por cliente y de 16 canales de invitado por sala. Hay latidos cada 5 s (solo si no se ha enviado nada más) y se da por perdido a quien lleva 20 s sin enviar nada. La clave `anon` del código es pública por diseño; no hay ninguna clave secreta en el cliente.

Limitaciones: si el anfitrión cierra la pestaña la sala termina; quien pierde la conexión en plena partida queda eliminado; los canales son públicos, así que cualquiera que adivine el código de sala podría leer o entrar; el anfitrión es quien manda y podría falsear una partida. No hay cuentas ni lista de amigos. El plan gratuito de Supabase Realtime tiene límites de conexiones y mensajes por segundo (ver su documentación oficial).

## Desarrollo

Servir por HTTP, no abrir el archivo directamente: `python3 -m http.server 8000`.

Regenerar diccionario y sílabas (`bomba/words.txt`, `bomba/syllables.json`). Si cambias los umbrales de dificultad en `tools/build-words.mjs`, actualiza también el texto de «Dificultad» en `bomba/index.html` (constante `HOW`):

```
npm install
npm run words
```

## Estructura

```
index.html            portada
shared.css            fuente, colores, botones e inputs comunes
bomba/index.html      el juego Bomba
tutti/index.html      el juego Tutti frutti (copia la capa de red de Bomba; si cambia una, cambia la otra)
teclazo/index.html    el juego Teclazo (misma capa de red copiada)
pistas/index.html     el juego Pistas (misma capa de red copiada)
pistas/palabras.json  palabras por letra (f fáciles, d difíciles; variantes aceptadas separadas por |; con Ñ y X la palabra contiene la letra)
teclazo/textos.json   refranes, frases y párrafos para las carreras (escritos para este proyecto o refranes populares)
teclazo/palabras.json palabras comunes para el modo Palabras
bomba/words.txt       diccionario normalizado (sin acentos)
bomba/syllables.json  sílabas por dificultad
bomba/examples.json   palabras de ejemplo por sílaba (para el resumen final)
vendor/               supabase-js (UMD) y Bricolage Grotesque (licencia OFL)
tools/build-words.mjs genera diccionario y sílabas
```

## Publicación

Sitio estático sin build: se sirve tal cual desde la raíz del repo, con rutas relativas. Destino: `https://games.pgfantasy.cat`, como proyecto de Cloudflare Pages propio conectado solo a este repo (sin build command; cabeceras en `_headers`). No comparte repo, proyecto, base de datos ni claves con ningún otro producto; del dominio raíz solo usa el subdominio. Los datos locales viven en `localStorage` del propio origen; las únicas cookies son las de Google AdSense (ver Publicidad).

## Estadísticas y panel de administración

Estadísticas propias y anónimas, sin terceros: `pg.js` guarda un identificador aleatorio en el navegador y envía eventos sueltos (visita, sala creada o unida, partida empezada o terminada, fallo de conexión) a la función `pg_log` del proyecto Supabase de pg games. Junto a las acciones de juego guarda el alias que el jugador escribe (máx. 14 caracteres) para que el panel, en su sección Jugadores, permita distinguir público real de pruebas propias y ocultar dispositivos (los ocultos no cuentan en ninguna estadística); además, al terminar cada partida quien la ha creado envía un resumen (alias de los jugadores, puntos, respuestas de Tutti frutti, palabras de Bomba y texto y velocidad de Teclazo) a la función `pg_game`, que el panel muestra en la ficha de cada jugador. Los dispositivos con «No rastrear» o `?notrack=1` no envían nada. Al añadir publicidad habrá que mencionarlo en la política de privacidad. No envía nada en localhost, con «No rastrear» activado ni en los dispositivos abiertos una vez con `?notrack=1` (`?notrack=0` vuelve a contar). Para que los dispositivos propios no cuenten en las cifras, lo recomendable es ocultarlos desde Jugadores: así sus salas siguen apareciendo en Actividad.

El panel está en `/admin/` (sin enlace desde la web, con `noindex`). Entra con un usuario de Supabase Auth cuyo correo esté en la tabla `admins`; los datos salen de la función `admin_stats`, que rechaza a cualquier otro usuario. La tabla de eventos no se puede leer ni escribir directamente desde la API. Todo el SQL (tablas, funciones y permisos) está en `supabase/schema.sql` y se puede ejecutar varias veces sin perder datos.

### Cambiar de juego en una sala

En el lobby, el anfitrión puede elegir otro juego. Envía `goto` a todos; cada uno abre el otro juego con el mismo código (`?host=CODIGO` el anfitrión, `?sala=CODIGO&go=1` los invitados) y vuelve a entrar solo con el nombre guardado. Los eventos y resúmenes de partida llevan el código de sala, y el panel los agrupa en la sección Actividad.

## Publicidad

Google AdSense, cuenta `ca-pub-6948133442454798`. El script va en el `<head>` de las páginas públicas (portada, juegos, reglas, sobre y privacidad), nunca en `/admin/` ni en `404.html`. El `ads.txt` está en la raíz del dominio (`pgfantasy.cat/ads.txt`, repo de PG Fantasy), porque AdSense solo admite el dominio raíz como sitio; es lo único que toca ese proyecto. El consentimiento RGPD lo gestiona el mensaje de "Privacidad y mensajes" de AdSense. Los anuncios automáticos deben quedar desactivados (o sin formatos superpuestos) para que no aparezcan durante las partidas; los bloques manuales irán en portada, lobby y resultados.

Páginas de texto (para AdSense y buscadores, enlazadas discretamente desde el pie de la portada): `sobre/`, `privacidad/` y `<juego>/reglas/`, con estilos en `doc.css`. Las reglas se generaron a partir de la constante `HOW` de cada juego: si cambian las reglas, actualiza también su página. `sitemap.xml` las lista todas.
