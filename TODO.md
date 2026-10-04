# TODO / Future Improvements

## Architecture
- [x] **Blocker for publishing to the registry/Pursuit:** the library depends on `sequences` through a git fork
      (`workspace.extraPackages` in `spago.yaml`: flip111/purescript-sequences, pinned commit). A registry package
      can't depend on a git package — needs the fork's changes released to the registry (upstream or as a new
      package), or `Seq` replaced/vendored. Decide at the public-interface step.
      Option worth trying first: our own `Fifo` instance as an Okasaki two-list ("banker's") queue — no
      dependency at all. `Seq` was chosen only for cheap concatenation in `replace`, but `replace skip` can be
      `skip` dequeues + `skip` enqueues: O(skip), skip <= kernel reach (<= 3). Enqueue/dequeue are O(1)
      amortized as long as each queue version is used once, which is how `step`/`ditherRow` use them.
      Prove it as a 5th backend in `DiffusionMechanicsSpec`, then benchmark against `Seq`.
      (done 2026-10-03: `Seq` replaced by `Data.CatQueue` from the registry package `catenable-lists` — the same
      two-list queue, ready-made rather than our own. `sequences` and the `extraPackages` entry are gone, so the
      library depends only on registry packages; and it's ~3.6× faster — `docs/benchmarks-dithering.md`.)
- [ ] **Public row-by-row stepper (public-interface step): reusing an old state.** `Fifo CatQueue` is O(1)
      amortized only if each queue version is used once. A reused old one repeats the list reversal it already
      did: still correct, just slower. Inside the library every state is used once, but a public stepper would
      let callers keep a state and run from it again (e.g. undo in the web demo). Its API docs must state "use
      each state once", or the design must handle reuse otherwise. See the `CatQueue` instance in `Puregrain.Internal.Fifo`
      and the `DitherState` doc comment in `Puregrain.Internal.State`.
- [ ] ditherImage: alias `Array Number` to PixelRow
- [ ] ditherImage: LL.List - maybe define custom impl here (diff to typeclass Fifo)

## Backend variants
- [ ] Полиморфная (по `Traversable f`) версия `ditherRow`/`ditherImage` вместо специализированной под `Array` — сравнить производительность (Array.mapAccumL vs Data.Traversable.mapAccumL).
- [ ] ST-based backend (кольцевой буфер, мутабельные массивы) — сравнить производительность с classic (FIFO/Lazy List) версией.
- [x] Data.Sequence-based Fifo вместо Data.List.Lazy — сравнить. (`Seq` was the production default `Fifo` backend — see `docs/benchmarks-fifo.md` — until `Data.CatQueue` replaced it on 2026-10-03.)
- [ ] Benchmark `Puregrain.Quantize.nearestLevel`: O(N) linear scan today vs. sort-once + binary search O(log N) (see the `TODO(benchmark)` note on it). Only worth changing if it shows up at realistic level counts. (2026-09-25 baseline: `--levels 4` costs ×1.06 of a plain threshold, so low priority — `docs/benchmarks-dithering.md`.)

## Algorithm configuration
- [ ] Noise dithering: thresholds from a seeded hash of the pixel's position (white noise), a `Quantize` over
      `Context` with no state, combinable with any kernel like `Puregrain.Ordered`. Needs a seed in `Context` (or
      closed over by the quantizer) and a deterministic hash. Blue-noise masks already work as custom threshold
      maps (`Puregrain.Ordered.compileThresholdMap`).
- [ ] Ostromoukhov's Variable Error Diffusion 
- [ ] Обобщить `Kernel + quantize` в единую конфигурацию алгоритма (см. раннюю идею `DitherAlgo` record). 
- [ ] Рассмотреть typeclass + Reader Monad для протаскивания конфигурации алгоритма через весь pipeline, вместо явной передачи параметрами.
- [x] Pass custom user data for itsown impl of `quantize`
      (covered 2026-10-03: a quantizer is a closure, so it captures whatever data it needs; with `Context` it
      can also look up per-pixel data, such as a mask, by the pixel's position.)
- [x] Maybe `quantize` has to know some stateful imformation as begin row-
      (done 2026-10-03: `Context { x, y }`, the pixel's position; `x == 0` is the row start. State carried over
      from earlier pixels isn't offered: quantizers stay pure, effectful ones are postponed.)

## Application
- [ ] Browser demo (Canvas API через FFI, purescript-canvas) — сравнение всех вариантов дизеринга visually.
- [ ] Метрики качества (PSNR/SSIM) для сравнения алгоритмов.

## Testing infrastructure
- [x] generate test-input.png  as well the same way as benchmark images (done: one generator, `scripts/generate-images.mjs`, for both — see `docs/test-images.md`)
- [x] Перейти с простых `Test.Assert`-тестов на `purescript-spec` (describe/it) для более структурированного вывода.
- [x] Добавить `purescript-quickcheck` и property-based тесты, начиная с:
  - `prop_backendsAgree` — реализовано как `Test.Puregrain.DiffusionMechanicsSpec`: все четыре `Fifo`-бэкенда (`CatQueue`, `List.Lazy`, `List`, `Array`) сверяются со независимым ST-based reference (`Test.Puregrain.Reference`), а не только друг с другом.
  - Инвариант длины выходной строки/картинки — не отдельная property, но покрыт неявно: `===` на `Array` уже требует равной длины, так что несовпадение длины валит тест.
  - [ ] Инвариант детерминизма для константного входа — всё ещё не проверен отдельной property (тривиально верен для чистых функций, но explicit-тест отсутствует).
- [x] `Arbitrary`-генераторы для `Kernel` (валидные ядра: сумма весов ≈ 1.0, хотя бы один forward и один downward offset) и для тестовых изображений разных размеров. (`Test.Puregrain.Arbitrary` — `TestKernel`/`TestImage`; заметка: сгенерированные ядра НЕ гарантируют сумму весов ≈ 1.0 явно, просто случайные веса в [0,1].)
- [x] `purescript-spec` также даст удобный selective test run (--example "pattern"/focus), не только структурированный вывод — учтено, переход уже сделан.
- [x] Use 'test-inpit.png' of different size as benchmark images. merge generation into 1 script (with scaling ability).
      without parameters it should generate 256x256 that can be used for visual control, other images should be integrated
      to automation performatce tests.
      (done: `scripts/generate-images.mjs` — gray + truecolor composites, `--size`/`--sizes`/`WxH`; default changed to 512² by
      decision, see `docs/test-images.md`. Benchmark automation on these images: `scripts/benchmark.mjs`
      (`npm run bench`), results in `docs/benchmarks-dithering.md`.)
- [x] `Test.Dither.Row`, `Test.Dither.Step` — migrated to
      `Test.Puregrain.RowSpec`/`Test.Puregrain.StepSpec` (property tests +
      shape invariants + ported regression examples + edge cases), old
      originals deleted, dead `Test.Main` references removed.
- [x] `Test.Dither.Image`, `Test.Dither.Playground`: leftover `Test.Assert`-style modules that never ran.
      Deleted in the `Puregrain.*` reshape (2026-10-04): `Image` only checked the output's row count and width,
      which the backend checks in `Test.Puregrain.DiffusionMechanicsSpec` already cover; `Playground` had no
      assertions at all.


## Future library extension directions (not in scope now)
- [ ] CMY/CMYK pixel types + GCR/UCR (gray component replacement / under
      color removal). Algebraically CMY(K) is identical to RGB(A) — same
      independent-`Ring`-channel shape, same `Scalable` — so the type
      itself is cheap to add later (a straightforward newtype + instances,
      same as RGB/RGBA, no new abstraction needed). The real work is GCR/
      UCR: deriving K from C/M/Y is a color-management step that has to
      happen *before* dithering, not something plain independent-channel
      error diffusion gives you — naive 4-independent-channel diffusion is
      representable in this architecture today but isn't real print-
      quality CMYK output on its own (no per-channel screen angles, no
      moiré avoidance). Needs a concrete print/halftone target to justify.
- [ ] Block-constrained output — a different kind of algorithm, out of scope for now. The real ZX Spectrum look
      (2 colors per 8×8 cell), C64 multicolor modes, and pseudo-graphics (ANSI/Unicode block characters,
      PETSCII, teletext mosaics) all restrict each *cell* rather than each pixel. The per-pixel `Quantize`
      can't see a cell, so it needs a cell step first — choose each cell's colors (or its character plus
      foreground/background), then dither inside the cell with that small palette (reusable:
      `nearestColor` on a 2-color palette). The per-pixel presets (`zxSpectrum`, `c64`) exist today.
- [ ] Ordered dithering against a palette (vectorED) — not supported: `Puregrain.Ordered` decides between two
      neighbouring levels per channel, and a palette's colors have no such order. Needs a different method,
      e.g. Joel Yliluoma's positional dithering algorithms. Until then, palettes that are a grid of per-channel
      levels work through `--levels` (`--levels 6` = web-safe). See docs/ordered-dithering.md, "Not supported".
- [ ] `distance2Lab` — CIELAB-space distance metric for `Puregrain.Palette`,
      as a second argument to plug into `compilePalette`/
      `compilePaletteFromArray` alongside `distance2` (that's exactly what
      `CompiledPalette` packing the distance function was designed to make
      swappable — see `Puregrain.Palette`). Requires an RGB→Lab conversion
      (through XYZ, with a chosen white point/gamma assumption) that
      doesn't exist yet anywhere in this codebase.

## Kernels
нужна функция normalizeKernel/fillGaps, которая на входе берёт Kernel, а на выходе гарантирует, что для каждого dy от 1 до maxDepth есть все offset'ы в согласованном диапазоне dx (недостающие — добавляются с weight=0.0), чтобы каждый слой past[i]/future[i] имел одинаковую, предсказуемую форму (тот же набор FIFO по количеству и порядку) для любого dy.