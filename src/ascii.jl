# ─────────────────────────── ASCII front end ────────────────────────
#
# Each character cell is a grid point (dx units wide, dy units tall). Wire characters:
#   -   horizontal wire          |   vertical wire
#   +   corner / junction        *   junction with an explicit dot
#   )   crossing (no connection, no dot)
# A '-' touching a '|' (or '+') joins it; cells where three or more wires meet get a dot.
#
# Words are components, keyed by their first letter (SPICE style):
#   R C L            resistor, capacitor, inductor
#   D                diode; marker gives the cathode side: D1> <D1 D1^ D1v
#   O                open circuit with voltage marks: '+' and '−' at its ends and a label
#                    from the name (Ovgs → v_gs; O1 has none), same markers as V
#   V I              independent sources; marker points to '+' (V, default left/top) or
#                    along the arrow (I, default right/down)
#   E H / G F        dependent voltage / current sources (diamonds), same markers as V / I
#   -|N1  -|P1       MOSFET, gate bar on the left (N1|- mirrors it). N: drain on top;
#                    P: source on top. -|Q1 is an npn BJT (collector on top).
#   OA1              op-amp: + input wire from above, − from below, output to the right
#   gnd vdd vcc vss vee   ground and supply rails
#   any other lowercase word   a named terminal (open circle with the name)
#   @name            node tag (italic name, no circle). Inline in a wire (--@vx--) it
#                    labels the wire above; next to a wire end or under/over a wire it
#                    labels that point. Names may contain letters, digits and '_'.
#   ~i1>             current arrow inline in a wire (--~i1>-- or between '|' cells), label
#                    from the name (~i1 → i_1, ~iD → i_D). Markers give the direction:
#                    ~i1> <~i1 ~i1^ ~i1v; the default is right / down. Annotation only.
#   "text"           caption centred on the quotes, e.g. a title under a stage; <"text"
#                    starts it at the opening quote and "text"> ends it at the closing
#                    one. May hold $…$ math; nothing inside the quotes is parsed.
# A word with wires left and right is horizontal; with wires above and below, vertical.

const KINDS = Dict('R' => :R, 'C' => :C, 'L' => :L, 'D' => :D, 'V' => :V, 'I' => :I,
                   'E' => :cV, 'H' => :cV, 'G' => :cI, 'F' => :cI,
                   'N' => :nmos, 'P' => :pmos, 'Q' => :npn, 'O' => :open)
const BIPOLES = (:R, :C, :L, :D, :V, :I, :sV, :sI, :cV, :cI, :open)
const POLAR = (:D, :V, :I, :sV, :sI, :cV, :cI, :open)
const SWITCHES = (:nmos, :pmos, :npn)
const WIRECH = ('-', '|', '+', '*', ')')

function kindof(n::AbstractString)
    if islowercase(n[1])
        n == "gnd" && return :gnd
        n in ("vdd", "vcc") && return :vdd
        n in ("vss", "vee") && return :vss
        return :port
    end
    startswith(n, "OA") && return :opamp
    # sinusoidal sources: "SVsig" is the voltage source Vsig, "SIb" the current source Ib
    length(n) >= 2 && n[1] == 'S' && n[2] in ('V', 'I') && return n[2] == 'V' ? :sV : :sI
    get(KINDS, n[1], :port)
end

deflabel(n) = length(n) == 1 ? n : string(n[1], "_{", n[2:end], "}")

# Voltage label of an open circuit: "Ovgs" → v_{gs}, "Oout" → o_{ut}… ; "O1" → none.
openlabel(n) = length(n) > 1 && isletter(n[2]) ? deflabel(n[2:end]) : ""

struct Tok
    name::String
    kind::Symbol
    row::Int
    c0::Int          # columns of the word itself
    c1::Int
    s0::Int          # columns including markers (< > ^ and a gate bar)
    s1::Int
    dir::Symbol      # polarity marker: :none, :left, :right, :up, :down
    gate::Symbol     # transistors: :none, :left, :right
end

function tokenize(g)
    toks = Tok[]
    for r in eachindex(g)
        row = g[r]
        ch(i) = 1 <= i <= length(row) ? row[i] : ' '
        c = 1
        while c <= length(row)
            if row[c] == '"' && (e = findnext(==('"'), row, c + 1)) !== nothing
                left, right = ch(c - 1) == '<', ch(e + 1) == '>'
                push!(toks, Tok(String(row[c+1:e-1]), :caption, r, c, e, c - left, e + right,
                                left ? :left : right ? :right : :none, :none))
                c = e + 1 + right
                continue
            end
            if row[c] == '@' && c < length(row) && (isletter(row[c+1]) || isdigit(row[c+1]))
                c0 = c + 1
                c = c0
                while c <= length(row) && (isletter(row[c]) || isdigit(row[c]) || row[c] == '_')
                    c += 1
                end
                push!(toks, Tok(String(row[c0:c-1]), :node, r, c0, c - 1, c0 - 1, c - 1, :none, :none))
                continue
            end
            if row[c] == '~' && c < length(row) && isletter(row[c+1])
                c0 = c + 1
                c = c0
                while c <= length(row) && (isletter(row[c]) || isdigit(row[c]) || row[c] == '_')
                    c += 1
                end
                name = String(row[c0:c-1])
                s0, s1, dir = c0 - 1, c - 1, :none
                if length(name) >= 2 && name[end] == 'v' && (length(name) == 2 || isdigit(name[end-1]))
                    name = name[1:end-1]; dir = :down
                elseif ch(c) == '>'
                    dir = :right; s1 += 1; c += 1
                elseif ch(c) == '^'
                    dir = :up; s1 += 1; c += 1
                elseif ch(s0 - 1) == '<'
                    dir = :left; s0 -= 1
                end
                push!(toks, Tok(name, :current, r, c0, c0 + length(name) - 1, s0, s1, dir, :none))
                continue
            end
            if !isletter(row[c])
                c += 1
                continue
            end
            c0 = c
            while c <= length(row) && (isletter(row[c]) || isdigit(row[c]))
                c += 1
            end
            c1 = c - 1
            name = String(row[c0:c1])
            kind = kindof(name)
            s0, s1, dir, gate = c0, c1, :none, :none
            if kind in POLAR
                if length(name) >= 2 && name[end] == 'v' && (length(name) == 2 || isdigit(name[end-1]))
                    name = name[1:end-1]; dir = :down
                elseif ch(c1 + 1) == '>'
                    dir = :right; s1 += 1
                elseif ch(c1 + 1) == '^'
                    dir = :up; s1 += 1
                elseif ch(c0 - 1) == '<'
                    dir = :left; s0 -= 1
                end
            end
            if kind in (:sV, :sI)
                name = name[2:end]                 # "SVsig" is the source Vsig
            elseif kind in SWITCHES
                if ch(c0 - 1) == '|'
                    gate = :left; s0 -= 1
                elseif ch(c1 + 1) == '|'
                    gate = :right; s1 += 1
                end
            end
            push!(toks, Tok(name, kind, r, c0, c1, s0, s1, dir, gate))
        end
    end
    toks
end

# Orthogonal path from a pin to a grid point: vertical, horizontal, vertical.
function lpath(a::Pt, b::Pt)
    (isapprox(a.x, b.x; atol=1e-9) || isapprox(a.y, b.y; atol=1e-9)) && return Wire(a, b)
    m = (a.y + b.y) / 2
    Wire(a, Pt(a.x, m), Pt(b.x, m), b)
end

"""
    ascii_schematic(art; elements=(), nodes=Dict(), style=:below, labels=Dict(),
                    dx=0.5, dy=0.8, kw...) -> Schematic

Turn ASCII art into a schematic (see the legend in the source).

- `elements`, `nodes`, `style`: annotations, matched to instance and node names in the
  drawing; see [`annotate`](@ref).
- `labels`: overrides the default label of any word or node tag, e.g.
  `Dict("R1" => raw"\$R_{load}\$")`.
- `dx`/`dy`: size of a character cell in circuit units. Other keywords go to `Schematic`,
  e.g. `xscale=1.5` / `yscale=0.8` to spread or tighten the layout while symbols and text
  keep their size.
"""
function ascii_schematic(art::AbstractString; elements=(), nodes=Dict(), style::Symbol=:below,
                         labels=Dict{String,String}(), dx=0.5, dy=0.8, kw...)
    g = [collect(replace(l, '\t' => "    ")) for l in split(art, '\n')]
    toks = tokenize(g)
    owner = Set{Tuple{Int,Int}}()
    for t in toks, c in t.s0:t.s1
        push!(owner, (t.row, c))
    end
    ch(r, c) = 1 <= r <= length(g) && 1 <= c <= length(g[r]) ? g[r][c] : ' '
    iswire(r, c) = ch(r, c) in WIRECH && (r, c) ∉ owner
    P(r, c) = Pt((c - 1) * dx, -(r - 1) * dy)
    hz(x) = x in ('-', '+', '*', ')')
    vt(x) = x in ('|', '+', '*', ')')
    items = Placed[]
    deg = Dict{Tuple{Int,Int},Int}()          # connections per wire cell → junction dots
    bump!(r, c) = (deg[(r, c)] = get(deg, (r, c), 0) + 1)
    lbl(t) = get(labels, t.name, deflabel(t.name))
    function above(t, cols=t.c0:t.c1)
        for c in cols
            iswire(t.row - 1, c) && return c
        end
        nothing
    end
    function below(t, cols=t.c0:t.c1)
        for c in cols
            iswire(t.row + 1, c) && return c
        end
        nothing
    end

    # 1. Wires: join neighbouring wire cells centre to centre. A ')' crossing is spanned by
    #    one horizontal and one vertical segment, so the crossing point is interior to both
    #    and the two wires stay unconnected in the netlist.
    for r in eachindex(g), c in eachindex(g[r])
        iswire(r, c) || continue
        if ch(r, c) == ')'
            if iswire(r, c - 1) && iswire(r, c + 1)
                push!(items, Wire(P(r, c - 1), P(r, c + 1))); bump!(r, c - 1); bump!(r, c + 1)
            end
            if iswire(r - 1, c) && iswire(r + 1, c)
                push!(items, Wire(P(r - 1, c), P(r + 1, c))); bump!(r - 1, c); bump!(r + 1, c)
            end
            continue
        end
        if iswire(r, c + 1) && ch(r, c + 1) != ')' && (hz(ch(r, c)) || hz(ch(r, c + 1)))
            push!(items, Wire(P(r, c), P(r, c + 1))); bump!(r, c); bump!(r, c + 1)
        end
        if iswire(r + 1, c) && ch(r + 1, c) != ')' && (vt(ch(r, c)) || vt(ch(r + 1, c)))
            push!(items, Wire(P(r, c), P(r + 1, c))); bump!(r, c); bump!(r + 1, c)
        end
    end

    # Where a terminal word (port, gnd, supply) attaches through its own wire: the symbol
    # position, the wire cell it connects to, and the side for its text; or nothing.
    function terminalspot(t)
        r = t.row
        y = P(r, t.c0).y
        ca, cb = above(t), below(t)
        ca !== nothing && return Pt(P(r, ca).x, y + 0.3dy), (r - 1, ca), :below
        cb !== nothing && return Pt(P(r, cb).x, y - 0.3dy), (r + 1, cb), :above
        iswire(r, t.s0 - 1) && return P(r, t.s0), (r, t.s0 - 1), :right
        iswire(r, t.s1 + 1) && return P(r, t.s1), (r, t.s1 + 1), :left
        nothing
    end

    # Open circuits reach across blank cells to the terminal or wire at each end, so their
    # ends can be terminals level with other wires: no connecting wires or bends needed.
    termcell = Dict{Tuple{Int,Int},Int}()          # cell → index of a terminal-like token
    for (i, t) in enumerate(toks)
        t.kind in (:port, :gnd, :vdd, :vss) || continue
        for c in t.s0:t.s1
            termcell[(t.row, c)] = i
        end
    end
    maxcol = maximum(length, g; init=0)
    function reach(r, c, dr, dc)                    # first non-blank cell from (r, c)
        while 1 <= r <= length(g) && 1 <= c <= maxcol
            haskey(termcell, (r, c)) && return (:term, termcell[(r, c)], r, c)
            iswire(r, c) && return (:wire, 0, r, c)
            ch(r, c) == ' ' || return nothing
            r += dr; c += dc
        end
        nothing
    end
    openends = Dict{Int,Tuple{Pt,Pt,Bool}}()        # open token → (first end, second end, horizontal)
    attached = Dict{Int,Tuple{Pt,Symbol,Bool}}()    # terminal token → (spot, text side, above the open?)
    for (i, t) in enumerate(toks)
        t.kind == :open || continue
        r = t.row
        ends, horizontal = nothing, false
        if !(iswire(r, t.s0 - 1) && iswire(r, t.s1 + 1))
            for c in t.c0:t.c1
                up, dn = reach(r - 1, c, -1, 0), reach(r + 1, c, 1, 0)
                if up !== nothing && dn !== nothing
                    ends = (up, dn)
                    break
                end
            end
        end
        if ends === nothing
            lf, rt = reach(r, t.s0 - 1, 0, -1), reach(r, t.s1 + 1, 0, 1)
            lf !== nothing && rt !== nothing && ((ends, horizontal) = ((lf, rt), true))
        end
        ends === nothing && continue
        pts = map(enumerate(ends)) do (j, e)
            kind_, ti, er, ec = e
            if kind_ == :wire
                bump!(er, ec)
                adjacent = horizontal ? ec == (j == 1 ? t.s0 - 1 : t.s1 + 1) : abs(er - r) == 1
                # a dangling wire end reached across a gap is an open-circuit terminal
                dangling = count(((u, v),) -> iswire(er + u, ec + v), ((1, 0), (-1, 0), (0, 1), (0, -1))) <= 1
                adjacent || !dangling || push!(items, Port(P(er, ec), "", horizontal ? (j == 1 ? :left : :right) : :left))
                return P(er, ec)
            end
            spot = terminalspot(toks[ti])
            spot === nothing || return spot[1]       # the terminal keeps its own wire and place
            side = horizontal ? (j == 1 ? :left : :right) : :left
            attached[ti] = (P(er, ec), side, j == 1)
            return P(er, ec)
        end
        openends[i] = (pts[1], pts[2], horizontal)
    end

    # 2. Components and terminals.
    for (ti, t) in enumerate(toks)
        r, k = t.row, t.kind
        if k == :open && haskey(openends, ti)
            first_, second_, horizontal = openends[ti]
            d = t.dir
            if (horizontal && d in (:up, :down)) || (!horizontal && d in (:left, :right))
                d = :none
            end
            a, b = d in (:right, :down) ? (second_, first_) : (first_, second_)   # '+' end first
            push!(items, Bipole(:open, a, b, ""; name=t.name))
            push!(items, Voltage(a, b, get(labels, t.name, openlabel(t.name)); side=:auto))
        elseif k in BIPOLES
            if iswire(r, t.s0 - 1) && iswire(r, t.s1 + 1)
                horizontal = true
                first_, second_ = P(r, t.s0 - 1), P(r, t.s1 + 1)
                bump!(r, t.s0 - 1); bump!(r, t.s1 + 1)
            else
                ca, cb = above(t), below(t)
                if ca === nothing && cb === nothing
                    @warn "$(t.name) has no wires on both sides; skipped"
                    continue
                end
                both = findfirst(c -> iswire(r - 1, c) && iswire(r + 1, c), t.c0:t.c1)
                c = both === nothing ? something(ca, cb) : t.c0 + both - 1
                horizontal = false
                first_, second_ = P(r - 1, c), P(r + 1, c)
                ca === nothing || bump!(r - 1, ca)
                cb === nothing || bump!(r + 1, cb)
                ca !== nothing && ca != c && push!(items, Wire(P(r - 1, c), P(r - 1, ca)))
                cb !== nothing && cb != c && push!(items, Wire(P(r + 1, c), P(r + 1, cb)))
            end
            d = t.dir
            if (horizontal && d in (:up, :down)) || (!horizontal && d in (:left, :right))
                d = :none
            end
            # Does the marker point at the right/bottom end? Defaults: diode cathode and
            # current arrow right/down, '+' left/top.
            to2 = d == :none ? k in (:D, :I, :sI, :cI) : d in (:right, :down)
            toward, other = to2 ? (second_, first_) : (first_, second_)
            a, b = k in (:V, :sV, :cV, :open) ? (toward, other) :
                   k in (:D, :I, :sI, :cI) ? (other, toward) : (first_, second_)
            if k == :open                  # an open circuit: just the voltage across it
                push!(items, Bipole(:open, a, b, ""; name=t.name))
                push!(items, Voltage(a, b, get(labels, t.name, openlabel(t.name)); side=:auto))
            else
                # both sinusoidal sources are drawn as CircuiTikZ's sV; the netlist tells
                # them apart by the name's letter (Vsig, Isig)
                push!(items, Bipole(k == :sI ? :sV : k, a, b, lbl(t); name=t.name))
            end

        elseif k in SWITCHES
            ca, cb = above(t), below(t)
            C = P(r, something(ca, cb, t.c0))
            gate = t.gate != :none ? t.gate : iswire(r, t.s0 - 1) ? :left : :right
            push!(items, Transistor(k, t.name, C; xflip=gate == :right, yflip=k == :pmos, label=lbl(t)))
            gc = gate == :left ? t.s0 - 1 : t.s1 + 1
            if iswire(r, gc)
                push!(items, Wire(C + Pt(gate == :left ? -TPIN : TPIN, 0), P(r, gc))); bump!(r, gc)
            end
            ca === nothing || (push!(items, lpath(C + Pt(0, TPIN), P(r - 1, ca))); bump!(r - 1, ca))
            cb === nothing || (push!(items, lpath(C + Pt(0, -TPIN), P(r + 1, cb))); bump!(r + 1, cb))

        elseif k == :opamp
            ca, cb = above(t), below(t)                       # + and − inputs
            xin = maximum(P(r, c).x for c in (ca, cb, t.c0) if c !== nothing) + 0.1
            O = Pt(xin + 0.5, P(r, t.c0).y)
            push!(items, Opamp(t.name, O; label=get(labels, t.name, "")))
            if ca !== nothing
                x = P(r, ca).x
                push!(items, Wire(P(r - 1, ca), Pt(x, O.y + 0.2), O + Pt(-0.5, 0.2))); bump!(r - 1, ca)
            end
            if cb !== nothing
                x = P(r, cb).x
                push!(items, Wire(P(r + 1, cb), Pt(x, O.y - 0.2), O + Pt(-0.5, -0.2))); bump!(r + 1, cb)
            end
            if iswire(r, t.s1 + 1)
                push!(items, Wire(O + Pt(0.5, 0), P(r, t.s1 + 1))); bump!(r, t.s1 + 1)
            end

        elseif k == :caption
            at = t.dir == :left ? P(r, t.c0) : t.dir == :right ? P(r, t.c1) : 0.5 * (P(r, t.c0) + P(r, t.c1))
            push!(items, Caption(at, t.name; align=t.dir == :none ? :center : t.dir))

        elseif k == :current
            text = get(labels, t.name, deflabel(t.name))
            through = findfirst(c -> iswire(r - 1, c) && iswire(r + 1, c), t.s0:t.s1)
            if iswire(r, t.s0 - 1) && iswire(r, t.s1 + 1)          # --~i1>--
                a, b = P(r, t.s0 - 1), P(r, t.s1 + 1)
                push!(items, Wire(a, b)); bump!(r, t.s0 - 1); bump!(r, t.s1 + 1)
                push!(items, Current(a, b, text; into=t.dir == :left))
            elseif through !== nothing                               # vertical run
                c = t.s0 + through - 1
                a, b = P(r - 1, c), P(r + 1, c)
                push!(items, Wire(a, b)); bump!(r - 1, c); bump!(r + 1, c)
                push!(items, Current(a, b, text; into=t.dir == :up))
            else
                @warn "current arrow ~$(t.name) is not inline in a wire; skipped"
            end

        elseif k == :node
            text = get(labels, t.name, t.name)
            cols = t.s0:t.s1
            ca, cb = above(t, cols), below(t, cols)
            through = findfirst(c -> iswire(r - 1, c) && iswire(r + 1, c), cols)
            if iswire(r, t.s0 - 1) && iswire(r, t.s1 + 1)          # --@vx--
                push!(items, Wire(P(r, t.s0 - 1), P(r, t.s1 + 1)))
                bump!(r, t.s0 - 1); bump!(r, t.s1 + 1)
                push!(items, NodeLabel(P(r, t.s0), t.name, :above; label=text))
            elseif through !== nothing                               # vertical run
                c = t.s0 + through - 1
                push!(items, Wire(P(r - 1, c), P(r + 1, c)))
                bump!(r - 1, c); bump!(r + 1, c)
                push!(items, NodeLabel(P(r, c), t.name, :right; label=text))
            elseif iswire(r, t.s0 - 1)                               # wire|@vx
                push!(items, NodeLabel(P(r, t.s0 - 1), t.name, :right; label=text))
            elseif iswire(r, t.s1 + 1)                               # @vx|wire
                push!(items, NodeLabel(P(r, t.s1 + 1), t.name, :left; label=text))
            elseif ca !== nothing                                    # under a wire
                push!(items, NodeLabel(P(r - 1, ca), t.name, :below; label=text))
            elseif cb !== nothing                                    # over a wire
                push!(items, NodeLabel(P(r + 1, cb), t.name, :above; label=text))
            else
                @warn "node tag @$(t.name) is not next to a wire; skipped"
            end

        else                                                  # :gnd, :vdd, :vss, :port
            # `facing`: where the connection is, seen from the symbol (:below = connected
            # from above, so a ground hangs down; :above = connected from below).
            spot = terminalspot(t)
            if spot !== nothing
                p, nb, side = spot
                push!(items, Wire(P(nb...), p)); bump!(nb...)
                facing = side
            elseif haskey(attached, ti)                # the end of an open circuit
                p, side, first_end = attached[ti]
                facing = first_end ? :above : :below   # above the open: connected from below
            else
                @warn "$(t.name) is not connected to anything; skipped"
                continue
            end
            if k == :gnd
                push!(items, Ground(p, facing == :above))
            elseif k in (:vdd, :vss)
                push!(items, Supply(p, get(labels, t.name, "V_{" * uppercase(t.name[2:end]) * "}"), facing != :below))
            else
                push!(items, Port(p, get(labels, t.name, t.name), side; name=t.name))
            end
        end
    end

    # 3. Junction dots.
    for ((r, c), n) in deg
        (ch(r, c) == '*' || (n >= 3 && ch(r, c) != ')')) && push!(items, Dot(P(r, c)))
    end
    s = Schematic(items; kw...)
    isempty(elements) && isempty(nodes) ? s : annotate(s, elements; nodes, style)
end

"""
    schem\"\"\" … \"\"\"

ASCII schematic literal: `ascii_schematic` of the text with default options. Like a raw
string, it does no interpolation, so `\$…\$` labels can be written directly. A notebook
cell ending in one displays the drawing.
"""
macro schem_str(s)
    :(ascii_schematic($s))
end
