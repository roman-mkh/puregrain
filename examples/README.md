# puregrain examples

Small programs that show the library at work. They make their images in
code and print them as text, so they need no image files: run them in a
terminal. For real PNG images, use the
[command-line tool](../cli/README.md).

| Example | What it shows |
|---|---|
| [QuickStart.purs](src/Puregrain/Examples/QuickStart.purs) | A gray gradient, and the same gradient dithered with Floyd–Steinberg: the quick start in the [main README](../README.md#getting-started) |
| [Compare.purs](src/Puregrain/Examples/Compare.purs) | The gradient dithered three ways: without diffusion (a hard edge), with Floyd–Steinberg (scattered dots) and with a Bayer pattern (a regular grid) |

They form the package `puregrain-examples` in this repository's spago
workspace, so the build compiles them along with the library and CI checks
that they still compile.

## Running them

From the repository root, after `npm install`:

```bash
npx spago run -p puregrain-examples -m Puregrain.Examples.QuickStart
npx spago run -p puregrain-examples -m Puregrain.Examples.Compare
```

The pictures are made for a dark background, where █ shows as white. On a
light background they look inverted: to fix that, reverse the `shades` list
in `QuickStart.purs`. The shades are just characters; add more, and
`render` uses them all.

## Trying variations in the REPL

Start the REPL with the examples package, and import the library, the
gradient and the renderer:

```text
npx spago repl -p puregrain-examples
> import Effect.Console (log)
> import Puregrain as P
> import Puregrain.Examples.QuickStart (gradient, render)
> log (render (P.ditherImage P.atkinson (P.threshold 128.0) gradient))
```

Then change one thing at a time, for example:

- another kernel: `P.jarvisJudiceNinke`, or `P.noDiffusion` for none;
- another threshold: with `P.noDiffusion`, `P.threshold 64.0` makes the
  image much lighter. With a kernel, the overall tone hardly changes: the
  error carries the brightness on to the neighbours, and only the dots
  move;
- 3 gray levels instead of 2: `P.nearestLevel (P.evenRamp 3)` in place of
  `P.threshold 128.0` (black, middle gray and white show as 3 of the 5
  shades).

`:q` leaves the REPL. The API reference, with every function, is on
[Pursuit](https://pursuit.purescript.org/packages/purescript-puregrain).
