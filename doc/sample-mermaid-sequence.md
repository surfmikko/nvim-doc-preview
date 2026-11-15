# Mermaid sequence diagram sample

Showcase of what the preview renders for `sequenceDiagram` today, and what
it does not. Open with `:DocPreview`. Status is tracked in `doc/plan.md` and
`doc/diagram-model.md`.

## Supported

### Participants, actors and aliases

```mermaid
sequenceDiagram
    actor U as User
    participant A as App
    participant D as Database
    U->>A: open page
    A->>D: query
    D-->>A: rows
    A-->>U: render
```

### All message operators

```mermaid
sequenceDiagram
    A->B: solid, no head
    A-->B: dotted, no head
    A->>B: solid, arrow
    A-->>B: dotted, arrow
    A-xB: solid, cross
    A--xB: dotted, cross
    A-)B: solid, async
    A--)B: dotted, async
```

### Self message

```mermaid
sequenceDiagram
    A->>A: think
    A->>B: done
```

### Activation bars, explicit and shorthand

```mermaid
sequenceDiagram
    A->>B: start
    activate B
    B->>C: work
    deactivate B
    A->>+B: call
    B-->>-A: reply
```

### Notes

```mermaid
sequenceDiagram
    A->>B: hello
    Note right of B: right note
    Note left of A: left note
    Note over A,B: spans both
```

### Autonumber

```mermaid
sequenceDiagram
    autonumber
    A->>B: first
    B->>C: second
    C-->>A: third
```

### Frames: loop, alt, opt, par, critical, break

```mermaid
sequenceDiagram
    loop every minute
        A->>B: ping
    end
    alt ok
        B->>A: 200
    else failed
        B->>A: 500
    end
    opt cached
        A->>A: use cache
    end
    par fetch
        A->>B: one
    and fetch
        A->>C: two
    end
    critical connect
        A->>B: open
    option timeout
        A->>A: retry
    end
    break stop
        A->>B: abort
    end
```

### Nested frames

```mermaid
sequenceDiagram
    loop retry
        A->>B: request
        alt success
            B-->>A: ok
        else error
            B-->>A: fail
        end
    end
```

### `rect` blocks (transparent: events laid out, no frame)

```mermaid
sequenceDiagram
    rect rgb(200, 220, 255)
        A->>B: inside
    end
```

### Parse error shows the source

```mermaid
sequenceDiagram
    A->>B: ok
    end
```

### Wide diagram: width fallbacks

Resize the preview narrow: spacing goes compact, message text wraps, then
the source is shown in a box.

```mermaid
sequenceDiagram
    participant Alpha
    participant Bravo
    participant Charlie
    participant Delta
    Alpha->>Delta: a long message text that needs room between far apart participants
    Delta-->>Alpha: another quite long reply
```

## Not implemented or approximated

### `box` grouping (kept balanced, not drawn)

```mermaid
sequenceDiagram
    box Aqua Frontend
        participant A
        participant B
    end
    A->>B: hi
```

### Ignored statements

`title`, `link`, `links`, `properties`, `details`, `destroy` and the
accessibility lines parse but have no effect.

```mermaid
sequenceDiagram
    title Not shown
    accTitle: not shown
    participant A
    participant B
    link A: Docs @ https://example.com
    A->>B: hi
    destroy B
```

### Message without text (accepted, mermaid.js rejects it)

```mermaid
sequenceDiagram
    A->>B
```

### Frames always span the full diagram width

The frame covers participants it does not involve.

```mermaid
sequenceDiagram
    participant A
    participant B
    participant C
    participant D
    loop only A and B
        A->>B: ping
    end
```

### Text across non-adjacent participants can overwrite a middle lifeline

```mermaid
sequenceDiagram
    participant A
    participant B
    participant C
    A->>C: a message long enough to cross the lifeline of B
```
