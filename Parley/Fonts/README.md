# Bundled fonts

All fonts here are licensed under the **SIL Open Font License 1.1** (see `OFL.txt`),
which permits bundling and redistribution inside an application. The variable
source fonts were instanced into the specific static weights this app uses.

| Family | Weights bundled | Copyright / source |
|--------|-----------------|--------------------|
| Newsreader | Regular, SemiBold | © The Newsreader Project Authors — github.com/productiontype/Newsreader |
| Hanken Grotesk | Regular, SemiBold | © The Hanken Grotesk Project Authors — github.com/marcologous/hanken-grotesk |
| Space Grotesk | Regular, Medium | © The Space Grotesk Project Authors — github.com/floriankarsten/space-grotesk |
| Archivo | Regular, Bold, ExtraBold | © The Archivo Project Authors — github.com/Omnibus-Type/Archivo |
| IBM Plex Mono | Regular, Medium | © 2017 IBM Corp. — github.com/IBM/plex |
| Fraunces | Regular, SemiBold | © The Fraunces Project Authors — github.com/undercasetype/Fraunces |
| Source Serif 4 | Regular, SemiBold | © Adobe — github.com/adobe-fonts/source-serif |
| Spectral | Regular, SemiBold | © Production Type — fonts.google.com/specimen/Spectral |
| Inter | Regular, Bold | © The Inter Project Authors — github.com/rsms/inter |

These are registered at launch via CoreText (`AppFonts.registerAll()`), so no
`Info.plist` entries are required, and the app degrades gracefully to system
fonts if a face is ever missing.
