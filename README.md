# pg games

Juegos cortos multijugador para jugar con amigos. Web estática, sin registro: se juega compartiendo un enlace.

Juegos: Bomba (`bomba/`), una sílaba, una palabra, pasa la bomba. Con ajustes de vidas, dificultad, tipo y duración de la mecha, orden de pase (círculo, rebote o azar) y más; las reglas están explicadas dentro del juego, en «Cómo se juega».

## Multijugador

WebRTC con PeerJS. Quien crea la sala es el anfitrión y lleva la partida (turnos, mecha, validación de palabras); los demás se conectan directamente a su navegador. El servidor público de PeerJS solo participa en el saludo inicial.

Limitaciones actuales: si el anfitrión cierra la pestaña la sala termina, y en redes muy restrictivas WebRTC puede no conectar al no haber servidor TURN propio. No hay cuentas ni lista de amigos.

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
bomba/index.html      el juego
bomba/words.txt       diccionario normalizado (sin acentos)
bomba/syllables.json  sílabas por dificultad
vendor/               PeerJS y Bricolage Grotesque (licencia OFL)
tools/build-words.mjs genera diccionario y sílabas
```
