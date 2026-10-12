# Third-party notices

FreeTheNotch is licensed under the GNU General Public License v3.0 or later (see [LICENSE](LICENSE)). It builds on the projects below; source files that use their code name the project in a header comment.

## GPL-3.0-or-later

- **Atoll** — https://github.com/Ebullioscopic/Atoll — Copyright (C) 2024-2026 Atoll Contributors. AI usage provider cards, quota/credential parsing, JSONL token accounting and price normalization are adapted from `DynamicIsland/managers/LLMUsage/` and `DynamicIsland/components/Notch/NotchLLMUsageView.swift`.
- **Vorssaint** — https://github.com/vorssaint/vorssaint-utils — Copyright (C) 2026 Vorssaint. Smooth mouse scrolling and its settings are adapted from `Services/SmoothScrollService.swift`, `Services/SmoothScrollSupport.swift`, `Services/ScrollWheelSupport.swift`, `Services/MouseExceptions/MouseAppExceptions.swift` and `UI/Settings/MouseSettings.swift`.

Both are licensed under the GNU General Public License v3.0 or later; the full text is in [LICENSE](LICENSE).

## MIT

The following license notices are reproduced as the MIT License requires.

### DuoBar

https://github.com/Mikeli7666/DuoBar

```
MIT License

Copyright (c) 2026 Mike Li

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

### CodeNotch

AI session lifecycle parsing and process liveness adapt `Sources/Sessions/CodexActivityMonitor.swift`, `ClaudeTranscript.swift`, `ClaudeSessionRecord.swift` and `ProcessLiveness.swift`.

AI usage price lookup and Claude streaming maxima also adapt `Sources/Costs/Pricing.swift`, `CostIndexer.swift` and `CostStore.swift`.

https://github.com/vinzdg/codenotch

```
MIT License

Copyright (c) 2026 Vinz

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

### LaunchAtLogin-Modern

https://github.com/sindresorhus/LaunchAtLogin-Modern

```
MIT License

Copyright (c) Sindre Sorhus <sindresorhus@gmail.com> (https://sindresorhus.com)

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```

## Apache-2.0

- **lottie-ios** — https://github.com/airbnb/lottie-ios — Copyright 2018 Airbnb, Inc. Linked as a Swift package for animation playback, under the Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0).

## Lottie Simple License

The bundled pet animations in `LottieAnimations/` are free animations from LottieFiles, used under the Lottie Simple License (https://lottiefiles.com/page/license):

- **Orange Cat Peeping** by Kanika — https://lottiefiles.com/free-animation/orange-cat-peeping-URGmInsHN3
- **Moody Dog** by Bashir — https://lottiefiles.com/free-animation/moody-dog-zVPveIAp02
- **Reindeer** by Bashir — https://lottiefiles.com/free-animation/reindeer-28s3dhfG3U
- **Tiger Happy** by Ludovic — https://lottiefiles.com/free-animation/tiger-happy-NTuAeRk1WH

## Zstandard (BSD-3-Clause)

The decode-only amalgamation is generated from [Zstandard v1.5.7](https://github.com/facebook/zstd/tree/v1.5.7), using upstream `build/single_file_libs/combine.py`. It decodes only Claude Desktop usage cache responses.

```text
BSD License

For Zstandard software

Copyright (c) Meta Platforms, Inc. and affiliates. All rights reserved.

Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:

 * Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

 * Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

 * Neither the name Facebook, nor Meta, nor the names of its contributors may
   be used to endorse or promote products derived from this software without
   specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR
ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

```
