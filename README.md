# pg games

Juegos cortos multijugador para jugar con amigos. Web estática, sin registro: se juega compartiendo un enlace.

Juegos: Teclazo (`teclazo/`), carrera de mecanografía en la que cada coche avanza según lo que escribes; se juega en sala o en individual contra la sombra de tu récord (ppm y precisión, guardados en el navegador). Tutti frutti (`tutti/`), una letra al azar y varias categorías que se pueden personalizar; se puntúa por respuestas únicas y los jugadores pueden votar las que no valen. Bomba (`bomba/`), una sílaba, una palabra, pasa la bomba. Con ajustes de vidas, dificultad, tipo y duración de la mecha, orden de pase (círculo, rebote o azar) y más; las reglas están explicadas dentro del juego, en «Cómo se juega». Tiene modo individual (aciertos, racha y récord, guardado en el navegador por combinación de ajustes), salir de la sala en cualquier momento y expulsión de jugadores por parte del anfitrión.

## Multijugador

Los mensajes pasan por brokers MQTT públicos (EMQX, HiveMQ y test.mosquitto.org) usando WebSocket seguro, así que no depende de la red de cada jugador. Quien crea la sala es el anfitrión y lleva la partida (turnos, mecha, validación de palabras); los demás le envían sus acciones. Cada cliente se conecta a todos los brokers a la vez y publica por todos; los mensajes duplicados se descartan, de modo que basta con que uno funcione. Hay latidos cada 3 s y se da por perdido a quien lleva 20 s sin responder.

Limitaciones actuales: si el anfitrión cierra la pestaña la sala termina; quien pierde la conexión en plena partida queda eliminado; los brokers son gratuitos y compartidos, sin garantías de servicio ni privacidad (no se envía nada sensible, pero cualquiera que adivine el código de sala podría leer o entrar). No hay cuentas ni lista de amigos. El plan de salida es Supabase Realtime con un proyecto propio: solo habría que cambiar la capa de red (`netOpen`, `netPub`).

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
vendor/               mqtt.js y Bricolage Grotesque (licencia OFL)
tools/build-words.mjs genera diccionario y sílabas
```
