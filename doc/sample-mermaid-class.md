# Mermaid class diagram sample

Showcase of what the preview renders for `classDiagram` today, and what it
does not. Open with `:DocPreview`. Status is tracked in `doc/plan.md` and
`doc/diagram-model.md`.

## Supported

### Class with annotation, members and methods

```mermaid
classDiagram
    class Animal {
        <<abstract>>
        +String name
        -int age
        +eat() void
        +sleep(hours) bool
    }
```

### All relation kinds

```mermaid
classDiagram
    A <|-- B : inheritance
    C *-- D : composition
    E o-- F : aggregation
    G --> H : association
    I -- J : link
    K ..> L : dependency
    M ..|> N : realization
    O .. P : dashed link
```

### Cardinalities and labels

```mermaid
classDiagram
    Customer "1" --> "*" Order : places
    Order "1" *-- "1..*" Line : contains
```

### Inheritance tree with members

```mermaid
classDiagram
    class Shape {
        <<interface>>
        +area() float
    }
    class Circle {
        +float radius
        +area() float
    }
    class Square {
        +float side
        +area() float
    }
    Shape <|.. Circle
    Shape <|.. Square
```

### Generics

```mermaid
classDiagram
    class Box~T~ {
        +T value
        +get() T
    }
    Box~int~ <|-- IntBox
```

### Notes

```mermaid
classDiagram
    class Cache
    note for Cache "Evicts least recently used"
    note "A general note"
```

### Namespace (drawn as a cluster)

```mermaid
classDiagram
    namespace Shapes {
        class Circle
        class Square
    }
    class Canvas
    Canvas --> Circle
    Canvas --> Square
```

### Direction

```mermaid
classDiagram
    direction LR
    Driver --> Car : drives
    Car *-- Engine
```

### Parse error shows the source

```mermaid
classDiagram
    class A {
        +broken(
    A <|-- 
```

### Wide diagram: width fallbacks

Resize the preview narrow: spacing goes compact, then top-down, then the
source is shown in a box.

```mermaid
classDiagram
    direction LR
    A --> B
    B --> C
    C --> D
    D --> E
    E --> F
```

## Not implemented or approximated

### Nested namespaces (syntax error)

```mermaid
classDiagram
    namespace Outer {
        namespace Inner {
            class A
        }
    }
```

### One-line class body (syntax error)

```mermaid
classDiagram
    class A { +x }
```

### Styling and links (parsed, ignored)

```mermaid
classDiagram
    class A
    class B
    A --> B
    style A fill:#f96
    cssClass "A" hot
    link A "https://example.com" "tooltip"
    click B call callback()
```

### Compact spacing loses connectors and cardinalities

Narrow the preview until the compact layout is used.

```mermaid
classDiagram
    Customer "1" --> "*" Order : places
    Order "1" *-- "1..*" Line : contains
    Line "*" --> "1" Product
```

### ASCII: triangle and open arrow look the same

Set `charset = "ascii"` and compare.

```mermaid
classDiagram
    A <|-- B
    C <-- D
```
