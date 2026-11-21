---
title: Run it in your browser
index: 6
---

# Run it in your browser

The samples run right here, in this page. They are the WebAssembly modules that `./build.sh --wasm`
makes and that the tests check, built from this site's version of the code: a few dozen kilobytes
each, and 1.1 MB for the language model, whose weights are inside it.

## Pick a sample and run it

Each sample runs as soon as you pick it: the terminal shows the command and what the program
prints, and the program's source is below it. Change the arguments or the input and run it again.

<div data-wasm-runner="../wasm/" class="not-prose wasm-runner">
  <div class="runner-picks" role="group" aria-label="Samples">
    <button type="button" data-sample="Llama" data-args="-n 200 -t 0.8 -s 7 -i &quot;The dragon&quot;" data-note="A language model of 260,000 parameters telling a story. Its weights are compiled into the 1.1 MB module. Change the length (-n), the seed (-s) or the start (-i).">Story model</button>
    <button type="button" data-sample="Llama" data-args="-c -s 3" data-stdin="Tom found a tiny robot in the garden.&#10;The robot said hello.&#10;&#10;Then they went home.&#10;" data-note="The same model taking turns: each line of standard input joins the story, and the model continues it. An empty line lets it go on by itself.">Take turns</button>
    <button type="button" data-sample="Quiz" data-stdin="46&#10;seven&#10;5&#10;17&#10;44&#10;&#10;74&#10;" data-note="The tutorial's quiz, answered from standard input: one line per question, and an empty line skips one.">Quiz</button>
    <button type="button" data-sample="Queries" data-note="Where, Select, GroupBy and friends over arenas, allocating nothing while they run.">Queries</button>
    <button type="button" data-sample="Records" data-note="Records, anonymous types and the ToString they generate.">Records</button>
    <button type="button" data-sample="Core" data-note="Math, Interlocked, extension members and C# 15 unions.">C# 15</button>
    <button type="button" data-sample="Strings" data-note="Strings without a garbage collector.">Strings</button>
    <button type="button" data-sample="Collections" data-note="Lists and maps in arenas.">Collections</button>
    <button type="button" data-sample="Casts" data-note="Casts, is, as and type patterns.">Casts</button>
    <button type="button" data-sample="Threads" data-note="Parallel.For. WebAssembly in a page has one thread, so the loop runs on it.">Threads</button>
    <button type="button" data-sample="Guards" data-args="list-index" data-note="A mistake lib/ stops the program for. Try restore-order or throw as the argument.">Guards</button>
    <button type="button" data-sample="Tiny" data-note="The smallest program.">Tiny</button>
  </div>
  <p data-sample-note></p>
  <div class="runner-panes">
    <div class="runner-term">
      <label class="term-command"><span aria-hidden="true">$ wasmtime <span data-module-name></span></span>
        <span class="visually-hidden">Arguments</span><input type="text" spellcheck="false"></label>
      <output aria-live="polite"></output>
      <p class="term-status" data-status></p>
      <details class="term-input">
        <summary>Standard input</summary>
        <textarea rows="4" spellcheck="false" aria-label="Standard input"></textarea>
      </details>
      <button type="button" data-run>Run</button>
    </div>
    <figure class="runner-source">
      <figcaption data-source-name>samples/</figcaption>
      <pre><code class="language-csharp" data-source></code></pre>
    </figure>
  </div>
</div>

## What the page does

The page gives each program what a terminal would: its arguments, standard input from the box, and
standard output and error printed below, with the exit code. That is all of WASI these programs use,
so the page implements it itself, in `docs/content/run-wasm.js`, instead of loading a library.

The programs run as they do under wasmtime, on one thread: WebAssembly here has no threads, so
`Parallel.For` runs its loop on the calling thread. [Run it on WebAssembly](webassembly.html) shows how
to build and run the same modules yourself.
