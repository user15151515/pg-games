# pg games

Juegos cortos multijugador para jugar con amigos. Web estática, sin registro: se juega compartiendo un enlace.

Juegos: Teclazo (`teclazo/`), carrera de mecanografía en la que cada coche avanza según lo que escribes; se juega en sala o en individual contra la sombra de tu récord (ppm y precisión, guardados en el navegador). Tutti frutti (`tutti/`), una letra al azar y varias categorías que se pueden personalizar; se puntúa por respuestas únicas y los jugadores pueden votar las que no valen. Bomba (`bomba/`), una sílaba, una palabra, pasa la bomba. Con ajustes de vidas, dificultad, tipo y duración de la mecha, orden de pase (círculo, rebote o azar) y más; las reglas están explicadas dentro del juego, en «Cómo se juega». Tiene modo individual (aciertos, racha y récord, guardado en el navegador por combinación de ajustes), salir de la sala en cualquier momento y expulsión de jugadores por parte del anfitrión.

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
teclazo/textos.json   refranes, frases y párrafos para las carreras (escritos para este proyecto o refranes populares)
teclazo/palabras.json palabras comunes para el modo Palabras
bomba/words.txt       diccionario normalizado (sin acentos)
bomba/syllables.json  sílabas por dificultad
bomba/examples.json   palabras de ejemplo por sílaba (para el resumen final)
vendor/               supabase-js (UMD) y Bricolage Grotesque (licencia OFL)
tools/build-words.mjs genera diccionario y sílabas
```

## Publicación

Sitio estático sin build: se sirve tal cual desde la raíz del repo, con rutas relativas. Destino: `https://games.pgfantasy.cat`, como proyecto de Cloudflare Pages propio conectado solo a este repo (sin build command; cabeceras en `_headers`). No comparte repo, proyecto, base de datos ni claves con ningún otro producto; del dominio raíz solo usa el subdominio. No usa cookies ni claves: el multijugador va por brokers MQTT públicos y los datos locales viven en `localStorage` del propio origen.
