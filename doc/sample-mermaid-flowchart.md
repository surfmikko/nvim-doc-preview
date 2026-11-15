# Mermaid flowchart sample

Showcase of what the preview renders for `flowchart` / `graph` today, and what
it does not. Open with `:DocPreview`. Status is tracked in `doc/plan.md` and
`doc/diagram-model.md`.

## Supported

### Directions

```mermaid
flowchart TD
    A[Top] --> B[Down]
```

```mermaid
flowchart LR
    A[Left] --> B[Right]
```

```mermaid
flowchart BT
    A[Bottom] --> B[Up]
```

```mermaid
flowchart RL
    A[Right] --> B[Left]
```

### Node shapes

```mermaid
flowchart LR
    r[Rect] --> ro(Round) --> st([Stadium]) --> sub[[Subroutine]]
    ci((Circle)) --> rh{Rhombus} --> hx{{Hexagon}} --> cy[(Cylinder)]
```

### Edge styles, heads and labels

```mermaid
flowchart TD
    A --> B
    A --- C
    A -.-> D
    A ==> E
    A <--> F
    A --o G
    A --x H
    B -->|label| I
    C -- text --> J
```

### Chains, fan-out and fan-in

```mermaid
flowchart TD
    A --> B --> C
    D & E --> F & G
```

### Labels: quotes and line breaks

```mermaid
flowchart LR
    A["Quoted: [text]"] --> B[Line<br/>break]
```

### Cycles and self-loops

```mermaid
flowchart TD
    A --> B --> C --> A
    C --> C
```

### Subgraphs, nested, with edges across the border

```mermaid
flowchart TD
    subgraph one [Outer]
        A --> B
        subgraph two [Inner]
            C --> D
        end
    end
    B --> C
    X --> A
    D --> Y
```

### Edge to a subgraph id

```mermaid
flowchart LR
    subgraph grp [Group]
        A --> B
    end
    S --> grp
```

### Parse error shows the source

```mermaid
flowchart TD
    A[unclosed --> B
```

### Wide diagram: width fallbacks

Resize the preview narrow: spacing goes compact, LR turns top-down, and
when nothing fits the source is shown in a box.

```mermaid
flowchart LR
    A[Alpha] --> B[Bravo] --> C[Charlie] --> D[Delta] --> E[Echo] --> F[Foxtrot]
```

## Not implemented or approximated

### Asymmetric and trapezoid shapes (drawn as rect)

```mermaid
flowchart LR
    A>Asymmetric] --> B[/Trapezoid/] --> C[\Alt trapezoid\]
```

### Styling (parsed, ignored)

```mermaid
flowchart LR
    A --> B
    classDef hot fill:#f96,stroke:#333
    class A hot
    style B fill:#9f6
    linkStyle 0 stroke:#f00
    click A callback "tooltip"
```

### Subgraph `direction` (ignored)

```mermaid
flowchart TD
    subgraph s [Wanted left to right]
        direction LR
        A --> B --> C
    end
```

### Edge to a subgraph attaches to its first member, not the border

```mermaid
flowchart LR
    subgraph grp [Group]
        A --> B
    end
    S --> grp
    grp --> T
```

### Opposite edges overlap on one line

```mermaid
flowchart LR
    A --> B
    B --> A
```

### Edge label dropped when no free cell is beside the line

```mermaid
flowchart TD
    A -->|one| B
    A -->|two| C
    A -->|three| D
    B --> E
    C --> E
    D --> E
```

### Compact spacing loses vertical connectors

Narrow the preview until the compact layout is used.

```mermaid
flowchart TD
    A[Alpha] -->|go| B[Beta] --> C[Gamma] --> D[Delta]
```

### Frontmatter config and `%%{init}%%` (skipped, no effect on drawing)

```mermaid
---
config:
  theme: dark
---
flowchart LR
    %%{init: {"theme": "forest"}}%%
    A --> B
```

### `@{ shape: ... }` node attributes (syntax error)

```mermaid
flowchart LR
    A@{ shape: cloud, label: "New shape syntax" } --> B
```
