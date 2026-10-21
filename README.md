# pg games

Juegos cortos multijugador para jugar con amigos. Web estática, sin registro: se juega compartiendo un enlace.

Juegos: Bomba (`bomba/`), una sílaba, una palabra, pasa la bomba.

## Multijugador

WebRTC con PeerJS. Quien crea la sala es el anfitrión y lleva la partida (turnos, mecha, validación de palabras); los demás se conectan directamente a su navegador. El servidor público de PeerJS solo participa en el saludo inicial.

Limitaciones actuales: si el anfitrión cierra la pestaña la sala termina, y en redes muy restrictivas WebRTC puede no conectar al no haber servidor TURN propio. No hay cuentas ni lista de amigos.

## Desarrollo

Servir por HTTP, no abrir el archivo directamente: `python3 -m http.server 8000`.

Regenerar diccionario y sílabas (`bomba/words.txt`, `bomba/syllables.json`):

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
