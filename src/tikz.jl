# ───────────────────────────── CircuiTikZ ───────────────────────────
#
# A reader for the common subset of CircuiTikZ: `\draw`/`\path`/`\node`/`\coordinate`
# statements with absolute, relative (`+`, `++`), polar and named coordinates, the path
# operations `--`, `|-`, `-|`, `to[...]` and `node[...]`, and the usual two-terminal
# elements, transistors, op-amps, grounds and supplies. Anything else is skipped with a
# warning, so a figure is never silently wrong.
#
# Geometry follows CircuiTikZ (coordinates in cm, y up): transistor and op-amp anchors are
# placed where CircuiTikZ puts them, so wires drawn to (M1.D) or ++(0,1) from an anchor
# meet the symbol. Polarity also follows CircuiTikZ: to[V] and to[cV] put '+' at the start
# of the path; to[I] and to[cI] point the arrow at the end.

# CircuiTikZ default dimensions, in cm (bipoles/length = 1.4cm times the tripole sizes).
const CTZ_MOS = (w=0.98, h=0.77)    # gate at -w, drain/source at ±h
const CTZ_BJT = (w=0.84, h=0.77)
const CTZ_OPAMP = (w=1.19, h=0.49)  # inputs at (-w, ±h), output at (w, 0)

const TIKZ_BIPOLES = Dict{String,Symbol}()
for (kind, names) in (
        :R => ("R", "resistor", "american resistor", "european resistor", "vR", "variable resistor"),
        :C => ("C", "capacitor", "eC", "ecapacitor", "pC", "polar capacitor", "cC", "curved capacitor", "vC"),
        :L => ("L", "inductor", "american inductor", "cute inductor", "european inductor", "cL", "vL"),
        :D => ("D", "diode", "D*", "full diode", "empty diode", "zD", "zD*", "Zener diode",
               "sD", "sD*", "Schottky diode", "leD", "leD*", "led"),
        :V => ("V", "vsource", "voltage source", "american voltage source", "vsourceAM",
               "battery1", "battery"),
        :I => ("I", "isource", "current source", "american current source", "isourceAM"),
        :sV => ("sV", "sinusoidal voltage source", "vsourcesin", "sI", "sinusoidal current source",
                "isourcesin"),
        :cV => ("cV", "cvsource", "controlled voltage source", "controlled vsource",
                "american controlled voltage source", "cvsourceAM", "csV"),
        :cI => ("cI", "cisource", "controlled current source", "controlled isource",
                "american controlled current source", "cisourceAM", "csI"),
        :short => ("short", "nos", "ncs"),
        :open => ("open",),
        :box => ("generic", "european resistor", "fuse"))
    for n in names
        haskey(TIKZ_BIPOLES, n) || (TIKZ_BIPOLES[n] = kind)
    end
end

const TIKZ_GROUNDS = ("ground", "tlground", "rground", "sground", "nground", "pground", "cground")
const TIKZ_UP_SUPPLIES = ("vcc", "vdd")
const TIKZ_DOWN_SUPPLIES = ("vee", "vss")
const TIKZ_TRANSISTORS = Dict("nmos" => :nmos, "nfet" => :nmos, "pmos" => :pmos, "pfet" => :pmos,
                              "npn" => :npn, "pnp" => :pnp)
const TIKZ_PINS = Dict("D" => :D, "drain" => :D, "S" => :S, "source" => :S, "G" => :G,
                       "gate" => :G, "C" => :C, "collector" => :C, "E" => :E, "emitter" => :E,
                       "B" => :B, "base" => :B,
                       "+" => :inp, "-" => :inn, "out" => :out)

# ─────────────── lexical helpers ───────────────

stripcomments(s) = replace(s, r"(?<!\\)%[^\n]*" => "")

# Index of the bracket closing the one at `i` (handles nesting and {} inside).
function closing(s::AbstractString, i::Int)
    open_ = s[i]
    close_ = open_ == '(' ? ')' : open_ == '[' ? ']' : '}'
    depth = 0
    j = i
    while j <= lastindex(s)
        c = s[j]
        if c == '{' && open_ != '{'
            j = closing(s, j)
        elseif c == open_
            depth += 1
        elseif c == close_
            depth -= 1
            depth == 0 && return j
        end
        j = nextind(s, j)
    end
    throw(ArgumentError("unbalanced '$open_'"))
end

# Split on `sep` at the top level (outside (), [], {} and \$…\$).
function splittop(s::AbstractString, sep::Char)
    parts = String[]
    depth = 0; math = false
    start = firstindex(s)
    for (i, c) in pairs(s)
        if c == '$'
            math = !math
        elseif !math && c in ('(', '[', '{')
            depth += 1
        elseif !math && c in (')', ']', '}')
            depth -= 1
        elseif c == sep && depth == 0 && !math
            push!(parts, s[start:prevind(s, i)])
            start = nextind(s, i)
        end
    end
    push!(parts, s[start:end])
    parts
end

unbrace(s) = (s = strip(s); startswith(s, '{') && endswith(s, '}') ? strip(s[2:end-1]) : s)

# "key=value" options → vector of (key, value) with value === nothing for bare keys.
function parseopts(s::AbstractString)
    out = Tuple{String,Union{Nothing,String}}[]
    for part in splittop(s, ',')
        part = strip(part)
        isempty(part) && continue
        k = findfirst('=', part)
        if k === nothing
            push!(out, (String(part), nothing))
        else
            push!(out, (String(strip(part[1:prevind(part, k)])), String(unbrace(part[k+1:end]))))
        end
    end
    out
end

# ─────────────── numbers ───────────────

const UNITS_CM = Dict("cm" => 1.0, "mm" => 0.1, "pt" => 1 / 28.4527, "in" => 2.54, "bp" => 2.54 / 72)

# A dimension or a small arithmetic expression ("2", "1.5cm", "2*0.75", "{3/2}").
function tikznum(s::AbstractString)
    s = replace(unbrace(s), " " => "")
    m = match(r"^(.*?)(cm|mm|pt|in|bp)$", s)
    f = 1.0
    if m !== nothing
        s, f = m.captures[1], UNITS_CM[m.captures[2]]
    end
    ex = try
        Meta.parse(s)
    catch
        throw(ArgumentError("can't read the number '$s'"))
    end
    f * evalarith(ex)
end

evalarith(x::Real) = Float64(x)
function evalarith(ex::Expr)
    if ex.head == :call && ex.args[1] in (:+, :-, :*, :/, :^)
        args = map(evalarith, ex.args[2:end])
        op = ex.args[1]
        return op == :+ ? sum(args) : op == :* ? prod(args) :
               op == :- ? (length(args) == 1 ? -args[1] : args[1] - args[2]) :
               op == :/ ? args[1] / args[2] : args[1]^args[2]
    end
    throw(ArgumentError("unsupported expression $ex"))
end
evalarith(x) = throw(ArgumentError("unsupported expression $x"))

# ─────────────── names and labels ───────────────

const SIUNITS = Dict("kilo" => "k", "mega" => "M", "giga" => "G", "milli" => "m", "micro" => "µ",
                     "nano" => "n", "pico" => "p", "femto" => "f", "ohm" => "Ω", "farad" => "F",
                     "henry" => "H", "volt" => "V", "ampere" => "A", "hertz" => "Hz",
                     "siemens" => "S", "watt" => "W", "second" => "s", "percent" => "%")

# CircuiTikZ's siunitx shorthand: "10<\micro H>" → "10 µH", "4.7<\kilo\ohm>" → "4.7 kΩ".
function siunitx(s::AbstractString)
    replace(s, r"<([^<>]*)>" => function (m)
        u = replace(m[2:end-1], r"\\([A-Za-z]+)" => w -> get(SIUNITS, w[2:end], w[2:end]))
        " " * replace(u, " " => "")
    end)
end

# Instance name from a label: "$R_{B1}$" → "RB1", "$v_{in}$" → "vin".
function name_from_label(s::AbstractString)
    s = replace(s, r"\\[a-zA-Z]+" => "")       # drop macros
    s = split(s, '=')[1]                         # "$R_1 = 10k$" → "$R_1 "
    filter(c -> isletter(c) || isdigit(c), s)
end

# ─────────────── parser state ───────────────

mutable struct TikzState
    items::Vector{Placed}
    named::Dict{String,Pt}                       # coordinates and plain nodes
    devices::Dict{String,Placed}                 # transistors and op-amps (have anchors)
    scale::Float64                               # environment scale= (coordinates)
    shapescale::Float64                          # … applied to symbols only with transform shape
end

warnskip(what) = @warn "tikz_schematic: $what"

function resolve(st::TikzState, ref::AbstractString)
    ref = strip(ref)
    if haskey(st.named, ref)
        return st.named[ref]
    end
    k = findlast('.', ref)
    if k !== nothing
        dev, a = ref[1:prevind(ref, k)], ref[k+1:end]
        if haskey(st.devices, dev)
            d = st.devices[dev]
            if haskey(TIKZ_PINS, a)
                p = TIKZ_PINS[a]
                if d isa Opamp && p in (:inp, :inn, :out)
                    return pin(d, p)
                elseif d isa Transistor && p in (:D, :S, :G, :C, :E, :B)
                    return pin(d, p)
                end
            end
            a in ("center", "mid") && return d.at
            warnskip("anchor '$a' of $dev not supported; using its centre")
            return d.at
        end
    end
    haskey(st.devices, ref) && return st.devices[ref].at
    if k !== nothing && haskey(st.named, ref[1:prevind(ref, k)])
        warnskip("anchor '$(ref[k+1:end])' of $(ref[1:prevind(ref, k)]) not supported; using its position")
        return st.named[ref[1:prevind(ref, k)]]
    end
    throw(ArgumentError("unknown coordinate ($ref)"))
end

# Parse the inside of "( … )" → absolute point (given the base point for relatives).
function coordinate(st::TikzState, inner::AbstractString)
    inner = strip(inner)
    if occursin('$', inner)
        throw(ArgumentError("calc expressions like ($inner) are not supported"))
    end
    # Perpendicular coordinates: (A |- B) = (A.x, B.y), (A -| B) = (B.x, A.y).
    for (opstr, combine) in (("|-", (a, b) -> Pt(a.x, b.y)), ("-|", (a, b) -> Pt(b.x, a.y)))
        k = findfirst(opstr, inner)
        if k !== nothing
            return combine(coordinate(st, inner[1:prevind(inner, first(k))]),
                           coordinate(st, inner[nextind(inner, last(k)):end]))
        end
    end
    parts = splittop(inner, ',')
    if length(parts) == 2
        return st.scale * Pt(tikznum(parts[1]), tikznum(parts[2]))
    end
    m = match(r"^([^:]+):([^:]+)$", inner)                   # polar (angle:radius)
    if m !== nothing
        θ, r = tikznum(m.captures[1]), tikznum(m.captures[2])
        return st.scale * Pt(r * cosd(θ), r * sind(θ))
    end
    resolve(st, inner)
end

# ─────────────── elements ───────────────

struct BipoleSpec
    kind::Symbol
    label::String
    note::String
    name::String
    side::Symbol          # :left for l= (CircuiTikZ default), :right for l_=
    invert::Bool
    start_mark::Char      # '*' dot, 'o' open circle, ' ' none
    end_mark::Char
end

function bipolespec(opts::AbstractString)
    kind = :short; label = ""; note = ""; vlabel = ""; name = ""; invert = false; side = :left
    sm = em = ' '
    found = false
    for (k, v) in parseopts(opts)
        if !found && haskey(TIKZ_BIPOLES, k)
            kind = TIKZ_BIPOLES[k]; found = true
            v === nothing || (label = v)
        elseif k in ("l", "l_", "l^", "label")
            label = something(v, "")
            side = k == "l_" ? :right : :left
        elseif k in ("a", "a_", "a^", "annotation")
            note = something(v, "")
        elseif k in ("v", "v_", "v^", "v<", "v>", "i", "i_", "i^", "i<", "i>")
            vlabel = something(v, "")
        elseif k in ("n", "name")
            name = something(v, "")
        elseif k == "invert"
            invert = true
        elseif v === nothing && (m = match(r"^([*o]?)-([*o]?)$", k)) !== nothing
            sm = isempty(m.captures[1]) ? ' ' : m.captures[1][1]
            em = isempty(m.captures[2]) ? ' ' : m.captures[2][1]
        elseif !found && v === nothing
            warnskip("unknown element '$k'; drawn as a box")
            kind = :box; found = true; label = k
        end
    end
    isempty(label) && kind in (:V, :I, :cV, :cI, :sV) && (label = vlabel)
    isempty(name) && (name = name_from_label(label))
    BipoleSpec(kind, siunitx(label), siunitx(note), name, side, invert, sm, em)
end

function mark!(st::TikzState, p::Pt, m::Char)
    m == '*' && push!(st.items, Dot(p))
    m == 'o' && push!(st.items, Port(p, "", :right))
end

function addbipole!(st::TikzState, a::Pt, b::Pt, spec::BipoleSpec)
    if spec.kind == :short
        push!(st.items, Wire(a, b))
    else
        # invert flips the symbol end to end; the label stays on the same side of the path
        x, y = spec.invert ? (b, a) : (a, b)
        side = spec.invert ? (spec.side == :left ? :right : :left) : spec.side
        push!(st.items, Bipole(spec.kind, x, y, spec.label; name=spec.name, note=spec.note, side))
    end
    mark!(st, a, spec.start_mark)
    mark!(st, b, spec.end_mark)
end

# Which side a plain text node sits on, from TikZ positioning keys.
function textside(opts)
    for (k, v) in opts
        w = first(split(k))
        w in ("right", "left", "above", "below") && return Symbol(w)
        if k == "anchor" && v !== nothing
            a = first(split(v))
            a == "west" && return :right
            a == "east" && return :left
            a == "south" && return :above
            a == "north" && return :below
        end
    end
    :right
end

# `node[opts](name) at (p) {text}` placed at `p`.
function addnode!(st::TikzState, p::Pt, optstr::AbstractString, name::AbstractString, text::AbstractString)
    opts = parseopts(optstr)
    keys_ = [k for (k, _) in opts]
    get_(key) = (i = findfirst(==(key), keys_); i === nothing ? nothing : opts[i][2])
    shape = findfirst(k -> k in TIKZ_GROUNDS || k in TIKZ_UP_SUPPLIES || k in TIKZ_DOWN_SUPPLIES ||
                           haskey(TIKZ_TRANSISTORS, k) || k == "op amp" || k in ("circ", "ocirc"), keys_)
    shape = shape === nothing ? nothing : keys_[shape]
    rot = get_("rotate")
    if rot !== nothing && mod(tikznum(rot), 360) != 0
        warnskip("rotate=$rot on node $(isempty(name) ? shape : name) is not supported; drawn upright")
    end
    xflip = get_("xscale") !== nothing && tikznum(get_("xscale")) < 0
    yflip = get_("yscale") !== nothing && tikznum(get_("yscale")) < 0
    anchor = get_("anchor")
    nm = String(name)

    if shape === nothing                                   # plain text node or named point
        isempty(nm) || (st.named[nm] = p)
        isempty(strip(text)) && return
        push!(st.items, NodeLabel(p, isempty(nm) ? name_from_label(text) : nm,
                                  textside(opts); label=String(text)))
    elseif shape in TIKZ_GROUNDS
        push!(st.items, Ground(p, yflip))
    elseif shape in TIKZ_UP_SUPPLIES || shape in TIKZ_DOWN_SUPPLIES
        push!(st.items, Supply(p, String(text), (shape in TIKZ_UP_SUPPLIES) != yflip))
    elseif shape == "circ"
        push!(st.items, Dot(p))
    elseif shape == "ocirc"
        push!(st.items, Port(p, String(text), :right))
    elseif shape == "op amp"
        inv_up = !(yflip || "noinv input up" in keys_)
        xflip && warnskip("mirrored op amp (xscale=-1) is not supported; drawn facing right")
        o = Opamp(nm, p; label=String(text), w=st.shapescale * CTZ_OPAMP.w, h=st.shapescale * CTZ_OPAMP.h, inv_up)
        if anchor !== nothing && anchor != "center"
            haskey(TIKZ_PINS, anchor) ? (o = Opamp(nm, p + (p - pin(o, TIKZ_PINS[anchor])); label=String(text),
                                                   w=o.w, h=o.h, inv_up)) :
                                        warnskip("op amp anchor=$anchor not supported")
        end
        push!(st.items, o)
        isempty(nm) || (st.devices[nm] = o)
    else                                                   # transistor
        kind = TIKZ_TRANSISTORS[shape]
        dims = kind in (:nmos, :pmos) ? CTZ_MOS : CTZ_BJT
        # CircuiTikZ p-type devices have the drain/collector at the bottom.
        yf = (kind in (:pmos, :pnp)) != yflip
        mk(at) = Transistor(kind, nm, at; xflip, yflip=yf, label=String(text),
                            w=st.shapescale * dims.w, h=st.shapescale * dims.h)
        t = mk(p)
        if anchor !== nothing && anchor != "center"
            if haskey(TIKZ_PINS, anchor) && TIKZ_PINS[anchor] in (:D, :S, :G, :C, :E, :B)
                t = mk(p + (p - pin(t, TIKZ_PINS[anchor])))
            else
                warnskip("transistor anchor=$anchor not supported")
            end
        end
        push!(st.items, t)
        isempty(nm) || (st.devices[nm] = t)
    end
end

# ─────────────── path interpreter ───────────────

# Reads "[opts]" / "(name)" / "at (c)" / "{text}" after the keyword `node` starting at `i`.
function readnode(st::TikzState, s::AbstractString, i::Int, here)
    optstr = ""; name = ""; at = nothing
    i = skipws(s, i)
    if i <= lastindex(s) && s[i] == '['
        j = closing(s, i); optstr = s[nextind(s, i):prevind(s, j)]; i = skipws(s, nextind(s, j))
    end
    if i <= lastindex(s) && s[i] == '('
        j = closing(s, i); name = strip(s[nextind(s, i):prevind(s, j)]); i = skipws(s, nextind(s, j))
    end
    if startswith(s[i:end], "at")
        i = skipws(s, i + 2)
        j = closing(s, i); at = coordinate(st, s[nextind(s, i):prevind(s, j)]); i = skipws(s, nextind(s, j))
    end
    text = ""
    if i <= lastindex(s) && s[i] == '{'
        j = closing(s, i); text = strip(s[nextind(s, i):prevind(s, j)]); i = nextind(s, j)
    end
    optstr, name, something(at, here), text, i
end

skipws(s, i) = (while i <= lastindex(s) && isspace(s[i]); i = nextind(s, i); end; i)

# Character at byte index i, or ' ' past the end (so keyword checks can peek safely).
charat(s, i) = checkbounds(Bool, s, i) && isvalid(s, i) ? s[i] : ' '

function runpath!(st::TikzState, s::AbstractString)
    cur = nothing           # pen position
    base = nothing          # reference for + / ++
    op = :move              # pending operation for the next coordinate
    spec = nothing          # pending to[...]
    midnodes = []           # nodes written between an operation and its target
    i = skipws(s, firstindex(s))
    while i <= lastindex(s)
        c = s[i]
        if c == '(' || (c == '+' && i < lastindex(s) && (s[i+1] == '(' || (s[i+1] == '+' && i + 1 < lastindex(s) && s[i+2] == '(')))
            rel = c == '+' ? (s[i+1] == '+' ? 2 : 1) : 0
            i += rel
            j = closing(s, i)
            inner = s[nextind(s, i):prevind(s, j)]
            local p
            op != :move && cur === nothing && throw(ArgumentError("path operation with no start point"))
            if rel > 0
                base === nothing && throw(ArgumentError("relative coordinate with no start point"))
                p = base + coordinate(st, inner)
                rel == 2 && (base = p)
            else
                p = coordinate(st, inner)
                base = p
            end
            if op == :line
                push!(st.items, Wire(cur, p))
            elseif op == :hv                                  # -| : horizontal then vertical
                push!(st.items, Wire(cur, Pt(p.x, cur.y), p))
            elseif op == :vh                                  # |- : vertical then horizontal
                push!(st.items, Wire(cur, Pt(cur.x, p.y), p))
            elseif op == :to
                addbipole!(st, cur, p, spec)
            end
            for (o, nm, t) in midnodes                          # pos=.5 on the segment
                addnode!(st, 0.5 * (cur + p), o, nm, t)
            end
            empty!(midnodes)
            cur = p; op = :move; spec = nothing
            i = nextind(s, j)
        elseif startswith(s[i:end], "--")
            op = :line; i += 2
        elseif startswith(s[i:end], "-|")
            op = :hv; i += 2
        elseif startswith(s[i:end], "|-")
            op = :vh; i += 2
        elseif startswith(s[i:end], "to") && !isletter(charat(s, i + 2))
            i = skipws(s, i + 2)
            optstr = ""
            if i <= lastindex(s) && s[i] == '['
                j = closing(s, i); optstr = s[nextind(s, i):prevind(s, j)]; i = nextind(s, j)
            end
            op = :to; spec = bipolespec(optstr)
        elseif startswith(s[i:end], "node") && !isletter(charat(s, i + 4))
            optstr, name, at, text, i = readnode(st, s, i + 4, cur)
            if op != :move && cur !== nothing
                push!(midnodes, (optstr, name, text))
            else
                at === nothing && throw(ArgumentError("node with no position"))
                addnode!(st, at, optstr, name, text)
            end
        elseif startswith(s[i:end], "coordinate")
            i = skipws(s, i + 10)
            if i <= lastindex(s) && s[i] == '['
                i = skipws(s, nextind(s, closing(s, i)))
            end
            j = closing(s, i); name = strip(s[nextind(s, i):prevind(s, j)])
            i = skipws(s, nextind(s, j))
            if startswith(s[i:end], "at")
                i = skipws(s, i + 2); k = closing(s, i)
                st.named[name] = coordinate(st, s[nextind(s, i):prevind(s, k)]); i = nextind(s, k)
            else
                cur === nothing && throw(ArgumentError("coordinate ($name) with no position"))
                st.named[name] = cur
            end
        elseif c == '['                                       # path options: ignored
            i = nextind(s, closing(s, i))
        elseif isspace(c)
            i = nextind(s, i)
        else
            m = match(r"^[a-z]+", s[i:end])
            what = m === nothing ? string(c) : m.match
            throw(ArgumentError("path operation '$what' is not supported"))
        end
    end
end

"""
    tikz_schematic(src; elements=(), nodes=Dict(), style=:below, kw...) -> Schematic

Read CircuiTikZ source (a `circuitikz` environment, or just its `\\draw` statements) and
return a `Schematic` that displays as SVG. Supports the common subset of CircuiTikZ (see
the README); statements it can't read are skipped with a warning. `elements`, `nodes`
and `style` add annotations as in [`annotate`](@ref); other keywords go to `Schematic`.

Coordinates are taken as cm, so the default `scale=50` draws 1 cm as 50 px.
"""
function tikz_schematic(src::AbstractString; elements=(), nodes=Dict(), style::Symbol=:below, kw...)
    s = stripcomments(src)
    scale = 1.0
    shapes = false
    m = match(r"\\begin\{(circuitikz|tikzpicture)\}(\[[^\]]*\])?(.*?)\\end\{\1\}"s, s)
    if m !== nothing
        if m.captures[2] !== nothing
            for (k, v) in parseopts(m.captures[2][2:end-1])
                k == "scale" && v !== nothing && (scale = tikznum(v))
                k == "transform shape" && (shapes = true)
            end
        end
        s = m.captures[3]
    end
    st = TikzState(Placed[], Dict{String,Pt}(), Dict{String,Placed}(), scale, shapes ? scale : 1.0)
    for stmt in splittop(s, ';')
        stmt = strip(stmt)
        isempty(stmt) && continue
        cm = match(r"^\\(draw|path|node|coordinate|ctikzset|tikzset)\b"s, stmt)
        if cm === nothing
            warnskip("skipped '$(first(stmt, 40))'")
            continue
        end
        cmd = cm.captures[1]
        rest = stmt[length(cm.match)+1:end]
        cmd in ("ctikzset", "tikzset") && continue
        try
            if cmd == "node" || cmd == "coordinate"
                runpath!(st, cmd * " " * rest)
            else
                runpath!(st, rest)
            end
        catch err
            err isa ArgumentError || rethrow()
            warnskip("$(err.msg) in '$(first(stmt, 60))'; the rest of that statement is skipped")
        end
    end
    sch = Schematic(st.items; kw...)
    isempty(elements) && isempty(nodes) ? sch : annotate(sch, elements; nodes, style)
end

"""`tikz\"\"\" … \"\"\"` — CircuiTikZ literal; displays as SVG in a notebook."""
macro tikz_str(s)
    :(tikz_schematic($s))
end
