# nvim-doc-preview: diagram engines and models

Diagram languages parse to `graph.model` (or their own model for sequence,
gantt, etc.) and share `graph/` for layout and drawing. Layout, pipeline and
dependency rules are in `doc/architecture.md`.

## 1. Mermaid engine

Interface (an engine in the sense of architecture 4.5):

```lua
mermaid.render(source_lines, ctx)
  --> Output  -- always returns Output; on failure, error box + source
```

Pipeline: detect type (first non-comment line, e.g. `flowchart TD`,
`sequenceDiagram`) -> type parser -> `graph.model` -> `graph/layout` ->
`graph/draw` on `core/canvas` -> Output (sequence diagrams use their own
linear layout). Types are registered in `registry.lua`; unknown or not yet
implemented types use `core/errbox` (boxed source listing, labelled with
the type name).

Supported types: flowchart/graph (nodes, edges, labels, shapes reduced to
box variants, subgraphs), sequence, class, state, ER, gantt, pie; others
fall back to boxed source.

Design notes:

* Node shapes are drawn with **border-glyph variants** on fixed-height
  (3-line) boxes, defined in `graph/shapes.lua` as a table
  `shape -> {corners, vertical, horizontal, label padding}`:

  ```
  rect      ┌───┐   round   ╭───╮   stadium (───)   rhombus ◇ or /─\
  subroutine ┌┬──┬┐ circle  (( ))   cylinder ╭─╮ with ═ base   hexagon <───>
  ```

  Unknown shapes fall back to rect. Using fixed height keeps layered
  layout and edge routing uniform; the final glyph table is in `doc/architecture.md` 10 item 1 and the
  `mermaid-flowchart-shapes-*` goldens.
* Pie (`mermaid/pie.lua`) shares nothing with `graph/`: a title line, then one
  horizontal bar per slice in source order (`█` with `▏..▉` eighths, ascii `#`),
  columns label, bar, integer percent and (with `showData`) the raw value.
  Percentages sum to 100 by largest remainder (all 0 when the total is 0);
  the bar scales 100% to at most 30 cells. Width policy: the bar shrinks to a
  minimum of 8 cells, then labels are cut with `...` (minimum 4 columns), then
  the boxed source with the note `diagram wider than N columns`. A negative or
  non-numeric value, and a pie without slices, give an errbox.
* Gantt (`mermaid/gantt.lua` parses and schedules, `gantt_draw.lua` draws):
  title, a tick row of dates (`MM-DD`, `YYYY-MM` over a year, `HH:mm` within
  a day; the smallest interval from 1 minute to a year whose labels do not
  touch), then per section a header row and one row per task: label column,
  a gap (`!` marks `crit`), bar area. The span of all tasks maps onto the bar
  area with `x(t) = floor((t - first) * W / span)`; `W` is a whole multiple of
  the span when the area is wider, so a unit is then several columns. Bars:
  `█` done, `▓` active, `░` otherwise, `◆` milestone (one column); ascii
  `#` `=` `-` `*`. A task always takes at least one column. Width policy:
  labels are cut with `...` to keep a bar area of 20 columns, then down to 10
  columns (labels at least 4, or their natural width if shorter), the scale
  gets coarser as the area shrinks, then the boxed source with the note
  `diagram wider than N columns`. Not applied: `axisFormat`, `tickInterval`,
  `todayMarker`, `excludes`, `includes`. A gantt without tasks is an errbox.
* The same `graph/` engine serves Graphviz `dot` (subset: digraph/graph,
  node/edge attributes `label`, `shape`, subgraph clusters, `rankdir`).
* Flowchart layout: layered (Sugiyama-style): cycle removal, layer
  assignment, ordering by barycenter, coordinate assignment on a
  character grid, orthogonal edge routing on the canvas. This is the
  largest piece of work; keep it isolated in `graph/layout.lua`.
* Subgraphs (`graph/cluster.lua`, `cluster_box.lua`): a cluster is a
  rectangle around its members and nested clusters, drawn with the title in
  its top border (left, or right if an edge enters there). Layout keeps
  members contiguous per layer, adds border/padding items per layer of the
  cluster's span, keeps sibling clusters in one order across layers and
  pushes non-members out of the rectangle; gaps between layers grow by one
  row per border plus one blank row where an edge enters or leaves. Edge
  routing jogs only in the free part of a gap, labels avoid clusters that
  hold neither edge end. An empty subgraph is a titled leaf box. An edge to
  or from a subgraph id attaches to the subgraph's first member (mermaid.js
  stops at the border); an edge between a subgraph and itself or one of its
  own members is dropped. Subgraph `direction` is parsed but ignored (the
  whole graph keeps one direction). An edge between two outsiders may still
  cross a cluster when the cluster order differs between layers.
* Sequence layout is linear: column per participant, row group per event
  (`mermaid/sequence_layout.lua`, drawn by `sequence_draw.lua`; both work on
  the syntax-free `sequence_model` so PlantUML P1 reuses them). Column x
  positions solve "c[j] >= c[i] + d" constraints from the participant boxes,
  message texts (centred above the arrow) and notes. Solid and dashed
  (dotted) arrows with `▶` (arrow), none (open), `x` (cross), `)` (async)
  heads next to the target lifeline; self-messages loop right of the
  lifeline; activation bars are thick lifeline segments; notes are boxes
  that cover the lifelines; `loop`/`alt`/`opt`/`par`/`critical`/`break` are
  full-width frames (nested ones inset by one column) with a `[type] label`
  title and dotted `[else]`/`[and]`/`[option]` dividers; `rect` is
  transparent. Participant boxes repeat at the bottom; actors have rounded
  corners; `autonumber` prefixes message texts with `N.`. Width policy as
  below, but the steps are: normal spacing, compact spacing, then compact
  with message/note text wrapped to 30, 20, 14, 10 and 6 columns, then the
  boxed source titled `diagram wider than N columns`.
* Width policy (`mermaid/flowchart.lua`; `graph/draw` reports the width the
  drawing needs, the canvas never writes past `ctx.width`). Each step is
  tried in order and the first drawing that fits is used: (1) normal
  spacing (compact when `ctx.compact`), (2) compact spacing (smaller gaps
  between layers and siblings), (3) for `LR`/`RL` the same graph laid out
  top-down with compact spacing, (4) the boxed source from `core/errbox`
  titled `diagram wider than N columns`. Node labels are cut with `...` to
  fit the width before drawing. Below 5 columns an errbox cannot be drawn,
  so the clipped drawing is returned. No output line is ever wider than
  `ctx.width` (asserted in unit, golden and integration tests).
* Class diagram (`mermaid/class.lua`, tokens in `class_syntax.lua`):
  parses to a `graph.model` of `record` nodes (id = class name, label =
  name with `~T~` shown as `<T>`; `rows` = non-empty sections annotation,
  members, methods; a member with `(` is a method; visibility and `$`/`*`
  stay as text). `g.classes[id]` keeps the sections by name for the facts
  projection. Relations map to edge `tail_kind`/`head_kind` (`<|`/`|>`
  triangle, `*` diamond_filled, `o` diamond, `<`/`>` arrow), `..` dotted,
  cardinalities to `tail_label`/`head_label`. Decision: a `namespace` is a
  cluster (graph subgraph; classes declared inside are its members), not
  a name prefix, so edges may cross its border and ids stay unchanged
  (revisit in the layout task if clusters of record nodes misbehave).
  Notes are record nodes `note:N` joined to their class by a dotted edge
  without ends. `classDef`, `cssClass`, `style`, `click`, `link`,
  `callback` are ignored.
  Drawing (task 16): `render` runs `parse -> graph.layout -> graph.draw`
  through `mermaid/fit.lua`, the width policy shared with the flowchart
  (compact spacing, LR/RL to top-down, boxed source; never wider than
  `ctx.width`). Default direction TD; `direction LR` is honoured until it
  does not fit. Glyph table (ascii in parentheses): inheritance `<|--`
  `△` (`^`) at the parent, `--|>` `▽` (`v`) at the parent; composition `*--`
  `◆` (`*`) and aggregation `o--` `◇` (`o`) at the whole; `-->`/`<--` arrow
  `▼ ▶` at the target; `..` dotted lines `┆ ┄`. Cardinalities sit beside
  their end, the relation label beside the line. Verified: record-node
  clusters (namespaces) draw correctly, with edges crossing the border, so
  the cluster decision stands. Known kit limits seen in goldens: a label
  with no free spot is dropped, and compact spacing (1-row gaps) puts both
  cardinalities of an edge on one row. Goldens `mermaid-class-*`.
* State diagram (`mermaid/state.lua`, tokens in `state_syntax.lua`):
  parses to a `graph.model` (states `round`, optional description `rows`;
  `[*]` is `start` as a source and `end` as a target, one pair per scope;
  `<<choice>>` `choice`, `<<fork>>`/`<<join>>` `bar`; notes are `record`
  nodes with a dotted edge). Composites are clusters titled in the border
  (`graph/cluster.lua`), their own `[*]` drawn inside; `--` regions are
  unnamed clusters. Drawing: `parse -> graph.layout -> graph.draw` through
  `mermaid/fit.lua` (same width policy as class and flowchart). Shape
  glyphs (ascii in parentheses), all label-free: start `●` (`(*)`), end `◉`
  (`(@)`), choice an empty rhombus `╱╲` 5x3, bar `━` x7 on a horizontal
  layout or `┃` x3 on `LR`/`RL` (`=`, `|`), each one marker row high in TD.
  Known limits: an edge to or from a composite id attaches to its first
  member (cluster rule), so it leaves the inner `[*]` and crosses the border;
  a `direction` inside a composite is ignored. Goldens `mermaid-state-*`.
* ER diagram (`mermaid/er.lua`, tokens in `er_syntax.lua`): parses to a
  `graph.model` of `record` nodes (title plus one aligned attribute
  section `type name keys "comment"`, aligned by display width) and edges
  with cardinality `tail_kind` (first entity) and `head_kind`. Drawing:
  `parse -> graph.layout -> graph.draw` through `mermaid/fit.lua` (the
  shared width policy). Identifying relationships are solid, non-identifying
  dotted (`┆ ┄`, ascii `: .`); the label sits beside the line. A cardinality
  end is two cells along the line, `graph/ends.lua`, near the border first:
  exactly one = bar bar, zero or one = bar `o`, zero or many = crow's foot
  `o`, one or many = crow's foot bar. Unicode: bar `╪` (vertical line) or
  `╫` (horizontal), crow's foot `┬ ┴ ├ ┤` (stem on the line, arms at the
  entity), zero `o`; ascii: bar `+`, crow's foot `v ^ > <` (apex on the
  line), zero `o`. The graph sets `end_room = 2` so the layout keeps gaps of
  at least 5 cells (two ends and a jog row). A self-relationship draws only
  the near cell of each end. Known limits: two relationships entering one
  entity share the merged line and ends (the labels may land on the jog
  row); a label with no free spot is dropped. Goldens `mermaid-er-*`.
* Canvas cells are display-width aware (wide chars are avoided; labels with
  wide glyphs are measured with `strdisplaywidth`).

## 2. PlantUML engine

Same interface as section 1 (`plantuml.render(source_lines, ctx) --> Output`, never
raises). Input is the text between `@startuml`/`@enduml` (fences `plantuml`,
`puml`; standalone `.puml`/`.plantuml` files render the whole buffer).
Detection is by content, since PlantUML has no type header: the first
diagram-specific statement decides (`participant`/`->` messages: sequence;
`class`/`interface`/`enum`: class; `start`/`:action;`: activity; `[*]`/`state`:
state; `actor`/`usecase`: use case; `component`/`node`: component;
`object`: object; `gantt`, `@startmindmap`/`@startgantt`: by start tag).
Types are registered in `registry.lua`; unknown or not yet implemented types
use `core/errbox` (boxed source listing, labelled with the type name).

| Type | Model / drawing |
|---|---|
| sequence | linear layout shared with `mermaid/sequence` |
| class | `graph.model` with multi-line record nodes |
| activity (new syntax), state, use case, component, object | `graph.model` + `graph/layout` |
| gantt, mindmap | own models |
| anything else | boxed source |

Not supported initially: `skinparam`, `!include`/preprocessor, sprites,
themes, creole markup beyond bold/italic (rendered as plain text).
