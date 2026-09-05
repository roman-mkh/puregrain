# TODO / Future Improvements

## Backend variants
- [ ] Полиморфная (по `Traversable f`) версия `ditherRow`/`ditherImage` вместо специализированной под `Array` — сравнить производительность (Array.mapAccumL vs Data.Traversable.mapAccumL).
- [ ] ST-based backend (кольцевой буфер, мутабельные массивы) — сравнить производительность с classic (FIFO/Lazy List) версией.
- [ ] Data.Sequence-based Fifo вместо Data.List.Lazy — сравнить.

## Algorithm configuration
- [ ] Обобщить `Kernel + quantize` в единую конфигурацию алгоритма (см. раннюю идею `DitherAlgo` record).
- [ ] Рассмотреть typeclass + Reader Monad для протаскивания конфигурации алгоритма через весь pipeline, вместо явной передачи параметрами.

## Application
- [ ] Browser demo (Canvas API через FFI, purescript-canvas) — сравнение всех вариантов дизеринга visually.
- [ ] Метрики качества (PSNR/SSIM) для сравнения алгоритмов.

## Testing infrastructure
- [ ] Перейти с простых `Test.Assert`-тестов на `purescript-spec` (describe/it) для более структурированного вывода.
- [ ] Добавить `purescript-quickcheck` и property-based тесты, начиная с:
  - `prop_backendsAgree` — classic (FIFO/Lazy List) и ST-based движок должны давать идентичный результат на случайных изображениях/ядрах.
  - Инвариант: длина выходной строки/картинки всегда равна длине входной.
  - Инвариант: для константного входного изображения результат детерминирован (одинаковый на повторных запусках).
- [ ] `Arbitrary`-генераторы для `Kernel` (валидные ядра: сумма весов ≈ 1.0, хотя бы один forward и один downward offset) и для тестовых изображений разных размеров.
- [ ] `purescript-spec` также даст удобный selective test run (--example "pattern"/focus), не только структурированный вывод   — учесть при приоритизации перехода.

## Kernels
нужна функция normalizeKernel/fillGaps, которая на входе берёт Kernel, а на выходе гарантирует, что для каждого dy от 1 до maxDepth есть все offset'ы в согласованном диапазоне dx (недостающие — добавляются с weight=0.0), чтобы каждый слой past[i]/future[i] имел одинаковую, предсказуемую форму (тот же набор FIFO по количеству и порядку) для любого dy.