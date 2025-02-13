# C64 BASIC tracker, by [lftkryo](https://www.youtube.com/@lftkryo)

This mostly the code that [Linus Åkesson](https://linusakesson.net/) wrote in his [YouTube video "Making 8-bit Music From Scratch at the Commodore 64 BASIC Prompt"](https://www.youtube.com/watch?v=ly5BhGOt2vE).

I transcribed a [transcription of the code from lemon64.com forum user `vma`](https://www.lemon64.com/forum/viewtopic.php?t=85608) which I OCR'd using Google Lens. That got me 95% there and only required some minor OCR fixes, and made for a great starting point. The transcript contained a few mistakes and omissions which I backfilled from the video. Once working, I made some minor improvements: The pitch-tables initialization is now skipped on subsequent runs and messages indicate what's happening while loading.

This was edited and tested using the excellent [VS64](https://github.com/rolandshacks/vs64) extension for [Visual Studio Code](https://code.visualstudio.com/), and compiled using [KickAssembler](https://theweb.dk/KickAssembler).