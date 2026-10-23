# ──────────────────────────── annotations ───────────────────────────
#
# Element objects are matched to drawn instances by name (case-insensitive, like SPICE).
# Any object with a `name` field and a `value` or `model` field works out of the box:
# your own structs, NamedTuples, etc. For other shapes, add methods to `instancename`
# and `annotation`.

"""
    instancename(e) -> String

Instance name used to match element object `e` to the drawing. Defaults to `e.name`.
"""
instancename(e) = string(getproperty(e, :name))

"""
    annotation(e) -> value, model string, or `nothing`

What to print for element object `e`: its `value` field if present (resistors,
capacitors, sources), otherwise its `model` field (transistors, diodes, op-amps).
"""
function annotation(e)
    for field in (:value, :model)
        if hasproperty(e, field)
            v = getproperty(e, field)
            v === nothing || return v
        end
    end
    nothing
end

const PREFIXES = ((1e9, "G"), (1e6, "M"), (1e3, "k"), (1.0, ""), (1e-3, "m"),
                  (1e-6, "µ"), (1e-9, "n"), (1e-12, "p"), (1e-15, "f"))

"""
    si(x, unit="") -> String

Engineering notation with an SI prefix and three significant digits:
`si(4700, "Ω") == "4.7 kΩ"`, `si(2.2e-9, "F") == "2.2 nF"`.
"""
function si(x::Real, unit::AbstractString="")
    tail(p) = isempty(p * unit) ? "" : " " * p * unit
    x == 0 && return "0" * tail("")
    i = findfirst(t -> abs(x) >= t[1] * (1 - 1e-9), PREFIXES)
    m, p = i === nothing ? last(PREFIXES) : PREFIXES[i]
    v = round(x / m; sigdigits=3)
    str = isinteger(v) && abs(v) < 1e15 ? string(Int(v)) : string(v)
    str * tail(p)
end

# Unit implied by the SPICE instance letter (G: transconductance, H: transresistance).
const UNIT_OF = Dict('R' => "Ω", 'C' => "F", 'L' => "H", 'V' => "V", 'I' => "A",
                     'G' => "S", 'H' => "Ω")

valuetext(v::Real, name) = si(v, get(UNIT_OF, isempty(name) ? ' ' : uppercase(name[1]), ""))
valuetext(v, name) = string(v)

# Escape text that will go through `texlabel` so model names like `nmos_lv` survive.
literal(s) = replace(s, "_" => "\\_")

"""
    annotate(s::Schematic, elements=(); nodes=Dict(), style=:below) -> Schematic

Return a copy of `s` with element values/models and node annotations added.

- `elements`: a collection of element objects (see `instancename`, `annotation`), or a
  dictionary `name => value`. Numbers are printed with SI prefixes and a unit implied by
  the instance letter (`R1 => 4700` → "4.7 kΩ"); anything else is printed as is.
- `nodes`: dictionary `node => annotation` for terminals (`vout`) and node tags (`@vx`).
  A number is appended as a voltage (`"vx" => 2.5` → "vx = 2.5 V"); a string replaces the
  displayed text (label syntax allowed, e.g. `raw"\$v_x\$ = 2.5 V"`).
- `style`: `:below` puts the value on a second line (opposite side from the name on
  horizontal parts, under it otherwise); `:inline` prints "R₁ = 4.7 kΩ" on one line;
  `:value` shows the value instead of the name.
"""
function annotate(s::Schematic, elements=(); nodes=Dict(), style::Symbol=:below)
    style in (:below, :inline, :value) ||
        throw(ArgumentError("style must be :below, :inline or :value, got :$style"))
    info = Dict{String,Any}()
    if elements isa AbstractDict
        for (k, v) in elements
            info[uppercase(string(k))] = v
        end
    else
        for e in elements
            v = annotation(e)
            v === nothing || (info[uppercase(instancename(e))] = v)
        end
    end
    nodeinfo = Dict{String,Any}(lowercase(string(k)) => v for (k, v) in nodes)

    function element(it)            # -> (label, note)
        key = uppercase(it.name)
        haskey(info, key) || return (it.label, it.note)
        text = valuetext(info[key], it.name)
        ismodel = it isa Union{Transistor,Opamp} || (it isa Bipole && it.kind == :D)
        if style == :below
            return (it.label, text)
        elseif style == :value || isempty(it.label)
            return (literal(text), "")
        else                        # :inline — "R₁ = 4.7 kΩ", "Q₁: 2N3904"
            return (it.label * (ismodel ? ": " : " = ") * literal(text), "")
        end
    end
    function node(it)
        key = lowercase(it.name)
        haskey(nodeinfo, key) || return it.label
        v = nodeinfo[key]
        v isa Real ? it.label * " = " * si(v, "V") : string(v)
    end

    items = map(s.items) do it
        if it isa Bipole
            l, n = element(it)
            Bipole(it.kind, it.a, it.b, l, it.name, n, it.side)
        elseif it isa Transistor
            l, n = element(it)
            Transistor(it.kind, it.name, it.at, it.xflip, it.yflip, l, n, it.w, it.h)
        elseif it isa Opamp
            l, n = element(it)
            Opamp(it.name, it.at, l, n, it.w, it.h, it.inv_up)
        elseif it isa Port
            Port(it.at, it.name, node(it), it.side)
        elseif it isa NodeLabel
            NodeLabel(it.at, it.name, node(it), it.side)
        else
            it
        end
    end
    Schematic(collect(Placed, items), s.scale, s.stroke, s.background, s.font)
end
