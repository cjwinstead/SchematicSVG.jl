# ──────────────────────────── container ─────────────────────────────
"""
    Schematic(items; scale=50, stroke="#222", background="white", font="serif",
              xscale=1, yscale=1, border=true)

A drawing: a list of placed primitives (`Bipole`, `Transistor`, `Wire`, …) and how to
render it. It displays as inline SVG in a notebook; [`to_svg`](@ref) gives the SVG text.
`ascii_schematic`, `tikz_schematic`, `annotate` and `layout` all return one.

- `scale`: pixels per circuit unit (it also sizes transistors and op-amps).
- `stroke`, `background`, `font`: line colour, background colour (`"none"` for
  transparent) and label font.
- `xscale`, `yscale`: spread the layout horizontally or vertically (or tighten it, below
  1) while symbols and text keep their size.
- `border`: a thick gray frame with rounded corners around the figure, so a drawing that
  runs past the edge of a notebook window is easy to spot.

`values` holds the element values the drawing was annotated with, by instance name; the
netlisters use them.
"""
Base.@kwdef struct Schematic
    items::Vector{Placed} = Placed[]
    scale::Float64 = 50.0        # px per circuit unit
    stroke::String = "#222"
    background::String = "white" # "none" for transparent
    font::String = "serif"
    values::Dict{String,Any} = Dict{String,Any}()   # raw element values/objects, by NAME
    xscale::Float64 = 1.0        # spread the layout horizontally / vertically; symbols and
    yscale::Float64 = 1.0        # text keep their size
    border::Bool = true          # thick gray rounded frame around the whole figure
end
Schematic(items::AbstractVector; kw...) = Schematic(; items=collect(Placed, items), kw...)

"""
    Schematic(s::Schematic; kw...)

A copy of `s` with some settings changed, e.g. `Schematic(s; xscale=1.5)` to spread a
drawing out horizontally, or `Schematic(s; background="none")`.
"""
function Schematic(s::Schematic; kw...)
    fields = Dict{Symbol,Any}(n => getfield(s, n) for n in fieldnames(Schematic))
    for (k, v) in kw
        haskey(fields, k) || throw(ArgumentError("Schematic has no setting `$k`"))
        fields[k] = v
    end
    Schematic(; fields...)
end

Base.show(io::IO, ::MIME"image/svg+xml", s::Schematic) = print(io, to_svg(s))

# ─────────────────────────── SVG backend ────────────────────────────
f(x) = string(round(x; digits=2))

xmlesc(s) = replace(s, "&" => "&amp;", "<" => "&lt;", ">" => "&gt;", "\"" => "&quot;")

px(s::Schematic, p::Pt) = Pt(s.scale * s.xscale * p.x, -s.scale * s.yscale * p.y)

"""Minimal LaTeX → SVG text: strips `\$`, turns `_x`/`_{xy}` into subscripts (`\\_` is a
literal underscore), maps a few macros. Returns (markup, number of visible characters). Subscripts use `dy` rather than
`baseline-shift`, which Firefox ignores."""
const TEXMACROS = Dict(
    "alpha" => "α", "beta" => "β", "gamma" => "γ", "delta" => "δ", "epsilon" => "ε",
    "varepsilon" => "ε", "eta" => "η", "theta" => "θ", "kappa" => "κ", "lambda" => "λ",
    "mu" => "μ", "nu" => "ν", "pi" => "π", "rho" => "ρ", "sigma" => "σ", "tau" => "τ",
    "phi" => "φ", "varphi" => "φ", "omega" => "ω", "Gamma" => "Γ", "Delta" => "Δ",
    "Theta" => "Θ", "Lambda" => "Λ", "Pi" => "Π", "Sigma" => "Σ", "Phi" => "Φ",
    "Omega" => "Ω", "infty" => "∞", "cdot" => "·", "times" => "×", "pm" => "±",
    "approx" => "≈", "parallel" => "∥", "ohm" => "Ω", "micro" => "µ", "degree" => "°")

function texlabel(s::AbstractString)
    s = replace(s, "\$" => "")
    # \mathrm{x}, \text{x}, … → x
    s = replace(s, r"\\(?:mathrm|text|textrm|mathit|mathsf|operatorname|mbox)\{([^}]*)\}" => s"\1")
    for (k, v) in ("\\," => " ", "\\;" => " ", "\\ " => " ", "\\!" => "")   # (one pair per call: Julia 1.6)
        s = replace(s, k => v)
    end
    # A control word swallows one following space, as in TeX: "\mu v" → "μv".
    s = replace(s, r"\\([A-Za-z]+) ?" => m -> get(TEXMACROS, m[2:end] |> rstrip, m))
    segs = Tuple{String,Bool}[]               # (text, is_subscript)
    i = firstindex(s)
    while i <= lastindex(s)
        c = s[i]
        if c == '\\' && i < lastindex(s) && s[nextind(s, i)] == '_'
            c = '_'                            # \_ is a literal underscore
            i = nextind(s, i)
            if !isempty(segs) && !last(segs)[2]
                segs[end] = (segs[end][1] * c, false)
            else
                push!(segs, (string(c), false))
            end
            i = nextind(s, i)
        elseif c == '_' && i < lastindex(s)
            j = nextind(s, i)
            if s[j] == '{'
                k = something(findnext('}', s, j), lastindex(s))
                push!(segs, (s[nextind(s, j):prevind(s, k)], true))
                i = nextind(s, k)
            else
                push!(segs, (string(s[j]), true))
                i = nextind(s, j)
            end
        else
            if c in ('{', '}')                  # grouping braces are not printed
            elseif !isempty(segs) && !last(segs)[2]
                segs[end] = (segs[end][1] * c, false)
            else
                push!(segs, (string(c), false))
            end
            i = nextind(s, i)
        end
    end
    out = IOBuffer()
    lowered = false
    for (t, sub) in segs
        if sub
            print(out, "<tspan dy=\"4\" font-size=\"10.5\">", xmlesc(t), "</tspan>")
            lowered = true
        elseif lowered
            print(out, "<tspan dy=\"-4\">", xmlesc(t), "</tspan>")
            lowered = false
        else
            print(out, xmlesc(t))
        end
    end
    String(take!(out)), sum(length(t) for (t, _) in segs; init=0)
end

"""Notes (values, model names) are literal text, so `nmos_lv` keeps its underscore.
Use `\$…\$` to opt in to the label syntax."""
notetext(s::AbstractString) = occursin('$', s) ? texlabel(s) : (xmlesc(s), length(s))

# ─────────────────────────────── text ───────────────────────────────
struct TextBox
    at::Pt                 # px
    anchor::String         # start | middle | end
    base::String           # auto | middle
    markup::String
    nchars::Int
    style::Symbol          # :label, :note, :node
end
TextBox(at, anchor, base, mt::Tuple, style) = TextBox(at, anchor, base, mt[1], mt[2], style)

# Label and optional note, stacked when they share a side (vertical text column).
function stacked(c::Pt, anchor, label, note)
    out = TextBox[]
    both = !isempty(label) && !isempty(note)
    isempty(label) || push!(out, TextBox(c + Pt(0, both ? -9 : 0), anchor, "middle", texlabel(label), :label))
    isempty(note)  || push!(out, TextBox(c + Pt(0, both ? 9 : 0), anchor, "middle", notetext(note), :note))
    out
end

"""All text drawn for an item: upright labels above horizontal parts (note below) and to
the right of vertical parts (note stacked under the label)."""
texts(s::Schematic, ::Placed) = TextBox[]

# One text box beside a part, on the side of unit normal `n` (page coordinates).
function beside(mid::Pt, n::Pt, dist, mt, style)
    c = mid + dist * n
    abs(n.x) > 0.5 && return TextBox(c, n.x > 0 ? "start" : "end", "middle", mt, style)
    TextBox(n.y < 0 ? c : c + Pt(0, 12), "middle", "auto", mt, style)
end

function texts(s::Schematic, b::Bipole)
    A, B = px(s, b.a), px(s, b.b)
    d = B - A
    u = (1 / hypot(d.x, d.y)) * d
    n = Pt(u.y, -u.x)                   # left of the a→b direction, as seen on the page
    hh = body(b.kind)[2] * symscale(b.kind, hypot(d.x, d.y))
    mid = 0.5 * (A + B)
    if b.side in (:left, :right)        # CircuiTikZ placement: label one side, note the other
        b.side == :right && (n = -1 * n)
        out = TextBox[]
        isempty(b.label) || push!(out, beside(mid, n, hh + 7, texlabel(b.label), :label))
        isempty(b.note)  || push!(out, beside(mid, -1 * n, hh + 7, notetext(b.note), :note))
        return out
    end
    if n.y > 1e-6 || (abs(n.y) < 1e-6 && n.x < 0)
        n = -1 * n                      # point up, or right for vertical parts
    end
    c = mid + (hh + 7) * n
    if abs(n.x) > 0.5                   # vertical-ish part: text column beside it
        return stacked(c, n.x > 0 ? "start" : "end", b.label, b.note)
    end
    out = TextBox[]
    isempty(b.label) || push!(out, TextBox(c, "middle", "auto", texlabel(b.label), :label))
    isempty(b.note)  || push!(out, TextBox(mid - (hh + 7) * n + Pt(0, 12), "middle", "auto",
                                           notetext(b.note), :note))
    out
end

function texts(s::Schematic, t::Transistor)
    k = s.scale * t.h / 25
    C = px(s, t.at)
    stacked(Pt(C.x + (t.xflip ? -1 : 1) * 24k, C.y), t.xflip ? "end" : "start", t.label, t.note)
end

function texts(s::Schematic, o::Opamp)
    C, k = opampgeom(s, o)
    out = TextBox[]
    isempty(o.label) || push!(out, TextBox(C + Pt(4k, -20k), "start", "auto", texlabel(o.label), :label))
    isempty(o.note)  || push!(out, TextBox(C + Pt(4k, 20k + 12), "start", "auto", notetext(o.note), :note))
    out
end

# A gate: its label above the body and its note below.
function texts(s::Schematic, g::Gate)
    C = px(s, g.at)
    H = s.scale * (gatehalf(g) + (g.kind == :tg ? 0.2 : 0.0))
    out = TextBox[]
    isempty(g.label) || push!(out, TextBox(C + Pt(0, -H - 5), "middle", "auto", texlabel(g.label), :label))
    isempty(g.note)  || push!(out, TextBox(C + Pt(0, H + 14), "middle", "auto", notetext(g.note), :note))
    out
end

# A block: pin names inside the box beside each pin, the label and note in the middle.
function texts(s::Schematic, b::Block)
    out = TextBox[]
    for p in b.pins
        isempty(p.name) && continue
        C = px(s, p.at)
        off, anchor, base = p.side == :left ? (Pt(5, 0), "start", "middle") :
                            p.side == :right ? (Pt(-5, 0), "end", "middle") :
                            p.side == :top ? (Pt(0, 14), "middle", "auto") : (Pt(0, -5), "middle", "auto")
        push!(out, TextBox(C + off, anchor, base, texlabel(p.name), :pin))
    end
    append!(out, stacked(0.5 * (px(s, b.lo) + px(s, b.hi)), "middle", b.label, b.note))
end

function texts(s::Schematic, u::Supply)
    isempty(u.label) && return TextBox[]
    C = px(s, u.at)
    [TextBox(C + Pt(0, u.up ? -9 : 18), "middle", "auto", texlabel(u.label), :label)]
end

const SIDE = Dict(:right => (Pt(7, 0), "start", "middle"), :left => (Pt(-7, 0), "end", "middle"),
                  :above => (Pt(0, -8), "middle", "auto"), :below => (Pt(0, 19), "middle", "auto"))

function texts(s::Schematic, p::Port)
    isempty(p.label) && return TextBox[]
    off, anchor, base = SIDE[p.side]
    [TextBox(px(s, p.at) + off, anchor, base, texlabel(p.label), :label)]
end

function texts(s::Schematic, c::Caption)
    [TextBox(px(s, c.at), c.align == :left ? "start" : c.align == :right ? "end" : "middle",
             "middle", notetext(c.text), :caption)]
end

# Node names sit just off the wire; above/below they start a little to the right of the
# point so a vertical wire through it doesn't strike through the text.
function texts(s::Schematic, n::NodeLabel)
    isempty(n.label) && return TextBox[]      # names a node without showing it
    off, anchor, base = n.side == :above ? (Pt(5, -6), "start", "auto") :
                        n.side == :below ? (Pt(5, 16), "start", "auto") : SIDE[n.side]
    [TextBox(px(s, n.at) + off, anchor, base, texlabel(n.label), :node)]
end

function render(io, ::Schematic, t::TextBox)
    style = t.style == :node ? " font-style=\"italic\"" : t.style == :note ? " font-size=\"13\"" :
            t.style == :pin ? " font-size=\"12\"" : ""
    print(io, "<text x=\"$(f(t.at.x))\" y=\"$(f(t.at.y))\" text-anchor=\"$(t.anchor)\" ",
              "dominant-baseline=\"$(t.base)\"$style stroke=\"none\" fill=\"currentColor\">",
              t.markup, "</text>")
end

# ────────────────────────────── symbols ─────────────────────────────
# Body of each bipole in a local frame: lies on the x axis, centred at 0, in px.
# Returns (half-width along the wire, half-height across it, svg markup).
const DIAMOND = 17
function body(kind::Symbol)
    if kind == :R
        return 20, 7, "<polyline points=\"-20,0 -16.7,-7 -10,7 -3.3,-7 3.3,7 10,-7 16.7,7 20,0\"/>"
    elseif kind == :C
        return 4, 13, "<line x1=\"-4\" y1=\"-13\" x2=\"-4\" y2=\"13\"/><line x1=\"4\" y1=\"-13\" x2=\"4\" y2=\"13\"/>"
    elseif kind == :L
        return 20, 5, "<path d=\"M-20,0 a5,5 0 0 1 10,0 a5,5 0 0 1 10,0 a5,5 0 0 1 10,0 a5,5 0 0 1 10,0\"/>"
    elseif kind == :D
        return 8, 9, "<polygon points=\"-8,-9 -8,9 8,0\" fill=\"none\"/><line x1=\"8\" y1=\"-9\" x2=\"8\" y2=\"9\"/>"
    elseif kind in (:V, :sV)
        return 15, 15, "<circle r=\"15\"/>"
    elseif kind == :I
        return 15, 15, "<circle r=\"15\"/>" * ARROW
    elseif kind in (:cV, :cI)
        D = DIAMOND
        return D, D, "<polygon points=\"-$D,0 0,-$D $D,0 0,$D\"/>" * (kind == :cI ? ARROW : "")
    elseif kind == :box                 # generic two-terminal (unknown CircuiTikZ parts)
        return 20, 8, "<rect x=\"-20\" y=\"-8\" width=\"40\" height=\"16\"/>"
    elseif kind in (:open, :short)
        return 0, 0, ""
    else
        error("unknown bipole kind $kind")
    end
end

# Current arrow a→b (drawn in the rotated frame, so it follows the element).
const ARROW = "<path d=\"M-8,0 h14\"/><polygon points=\"9,0 3,-4 3,4\" fill=\"currentColor\"/>"

# '+' and '−' are drawn in page coordinates so they stay upright; offset along the axis
# and half-size per symbol (the diamond needs more clearance from its slanted sides).
const SIGNS = Dict(:V => (9.0, 3.5), :cV => (6.5, 3.0))

# A two-terminal symbol has a fixed size in pixels, but its ends move closer when a
# drawing is squeezed (small `scale`, `xscale` or `yscale`). When they are closer than the
# symbol is long, the symbol shrinks (to no less than a quarter of its size) so that it
# keeps a lead of MINLEAD px at each end instead of running over the wires.
const MINLEAD = 4.0
function symscale(kind::Symbol, L::Real)
    hw = body(kind)[1]
    hw == 0 ? 1.0 : clamp((L / 2 - MINLEAD) / hw, 0.25, 1.0)
end

function render(io, s::Schematic, b::Bipole, ctx)
    A, B = drawn(s, ctx, b.a), drawn(s, ctx, b.b)
    d = B - A
    L = hypot(d.x, d.y)
    θ = atan(d.y, d.x) * 180 / π
    hw, _, svg = body(b.kind)
    k = symscale(b.kind, L)
    m = L / 2
    if b.kind != :open
        sym = k == 1 ? "translate($(f(m)),0)\"" :
              "translate($(f(m)),0) scale($(f(k)))\" stroke-width=\"$(f(1.5 / k))\""
        print(io, "<g transform=\"translate($(f(A.x)),$(f(A.y))) rotate($(f(θ)))\">",
                  "<line x1=\"0\" y1=\"0\" x2=\"$(f(m - k * hw))\" y2=\"0\"/>",
                  "<line x1=\"$(f(m + k * hw))\" y1=\"0\" x2=\"$(f(L))\" y2=\"0\"/>",
                  "<g transform=\"", sym, ">", svg, "</g></g>")
    end
    if b.kind == :sV                    # upright sine wave, whatever the direction
        c = 0.5 * (A + B)
        w = 9k
        print(io, "<path d=\"M$(f(c.x - w)),$(f(c.y)) q$(f(w / 2)),$(f(-w)) $(f(w)),0 t$(f(w)),0\"/>")
    end
    if haskey(SIGNS, b.kind)
        off, h = k .* SIGNS[b.kind]
        u = (1 / L) * d
        p = A + (m - off) * u              # '+' near a (the n+ terminal)
        q = A + (m + off) * u
        print(io, "<path d=\"M$(f(p.x - h)),$(f(p.y)) h$(f(2h)) M$(f(p.x)),$(f(p.y - h)) v$(f(2h)) ",
                  "M$(f(q.x - h)),$(f(q.y)) h$(f(2h))\"/>")
    end
end

# ─────────────────────────── voltage marks ──────────────────────────
# Page-coordinate frame of a Voltage: ends, unit direction plus → minus, the unit normal
# on its side, and the length.
function voltageframe(s::Schematic, v::Voltage)
    A, B = px(s, v.plus), px(s, v.minus)
    d = B - A
    L = hypot(d.x, d.y)
    u = (1 / L) * d
    left = Pt(u.y, -u.x)                 # left of plus → minus, as seen on the page
    n = v.side == :left ? left : v.side == :right ? -1 * left :
        (left.y > 1e-6 || (abs(left.y) < 1e-6 && left.x < 0)) ? -1 * left : left   # :auto
    A, B, u, n, L
end

# Where the '+' and '−' go: on the line near the ends of an open circuit, or flanking the
# symbol of a component.
function signspots(s::Schematic, v::Voltage)
    A, B, u, n, L = voltageframe(s, v)
    if v.kind == :open
        e = min(14.0, 0.25L)
        return A + e * u, B - e * u
    end
    hw, hh = symscale(v.kind, L) .* body(v.kind)[1:2]
    mid = 0.5 * (A + B)
    mid - (hw + 8) * u + (hh + 7) * n, mid + (hw + 8) * u + (hh + 7) * n
end

function render(io, s::Schematic, v::Voltage, _)
    p, m = signspots(s, v)
    h = 3.5
    print(io, "<path d=\"M$(f(p.x - h)),$(f(p.y)) h$(f(2h)) M$(f(p.x)),$(f(p.y - h)) v$(f(2h)) ",
              "M$(f(m.x - h)),$(f(m.y)) h$(f(2h))\"/>")
end

function texts(s::Schematic, v::Voltage)
    isempty(v.label) && return TextBox[]
    A, B, u, n, L = voltageframe(s, v)
    mid = 0.5 * (A + B)
    mt = texlabel(v.label)
    if v.kind == :open
        # horizontal open circuit: the label sits on the line between the signs
        abs(u.y) < 0.5 && return [TextBox(mid, "middle", "middle", mt, :label)]
        return [beside(mid, n, 6, mt, :label)]
    end
    hh = body(v.kind)[2] * symscale(v.kind, L)
    [beside(mid, n, hh + 7, mt, :label)]
end

# ─────────────────────────── current arrows ─────────────────────────
# Page-coordinate frame of a Current: the arrow's centre, its unit direction and the unit
# normal on its label side.
function currentframe(s::Schematic, c::Current)
    A, B = px(s, c.a), px(s, c.b)
    d = B - A
    L = hypot(d.x, d.y)
    u = (1 / L) * d
    left = Pt(u.y, -u.x)                 # left of a → b, as seen on the page
    n = c.side == :left ? left : c.side == :right ? -1 * left :
        (left.y > 1e-6 || (abs(left.y) < 1e-6 && left.x < 0)) ? -1 * left : left   # :auto
    hw = c.kind in (:short, :open) ? 0.0 : body(c.kind)[1] * symscale(c.kind, L)
    t = hw == 0 ? c.pos * L :                        # on a wire: where asked
        c.pos >= 0.5 ? (3L + 2hw) / 4 : (L - 2hw) / 4  # mid-lead after / before the symbol
    A + t * u, c.into ? -1 * u : u, n
end

function render(io, s::Schematic, c::Current, _)
    C, u, _ = currentframe(s, c)
    print(io, arrowhead(C + 3.5 * u, u; len=7, w=3.5))
end

function texts(s::Schematic, c::Current)
    isempty(c.label) && return TextBox[]
    C, _, n = currentframe(s, c)
    [beside(C, n, 7, texlabel(c.label), :label)]
end

function arrowhead(tip::Pt, dir::Pt; len=5, w=2.5)
    u = (1 / hypot(dir.x, dir.y)) * dir
    p = Pt(-u.y, u.x)
    bc = tip - len * u
    q1, q2 = bc + w * p, bc - w * p
    "<polygon points=\"$(f(tip.x)),$(f(tip.y)) $(f(q1.x)),$(f(q1.y)) $(f(q2.x)),$(f(q2.y))\" fill=\"currentColor\"/>"
end

# Symbol in local units with top pin (0,-25), bottom pin (0,25) and the control pin at
# (gx,0); gx = -25 when the gate is as far from the centre as the drain.
function tbody(kind::Symbol, gx=-25, ty=25)
    if kind in (:npn, :pnp)
        s = "<circle cx=\"-4\" cy=\"0\" r=\"17\"/>" *
            "<path d=\"M$(f(gx)),0 H-10 M-10,-12 V12 M-10,-5 L0,-15 V$(f(-ty)) M-10,5 L0,15 V$(f(ty))\"/>"
        dir = Pt(10, 10)
        s *= kind == :npn ? arrowhead(Pt(-2, 13), dir) : arrowhead(Pt(-8, 7), -1 * dir)
        return s
    else # :nmos, :pmos
        ge = kind == :pmos ? -20 : -14
        s = "<path d=\"M$(f(gx)),0 H$ge M-14,-10 V10 M-10,-13 V13 M-10,-8 H0 V$(f(-ty)) M-10,8 H0 V$(f(ty))\"/>"
        kind == :pmos && (s *= "<circle cx=\"-17\" cy=\"0\" r=\"3\"/>")
        s *= kind == :nmos ? arrowhead(Pt(-2, 8), Pt(1, 0)) : arrowhead(Pt(-8, 8), Pt(-1, 0))
        return s
    end
end

# ───────────────────────────── pins ─────────────────────────────────
# A symbol keeps its size under xscale/yscale, so its leads stretch or shrink to reach the
# scaled pin positions, but never into the symbol itself: a pin is drawn at least this far
# from the centre (local units, where the default pins are at 25). Wires that end on a pin
# end where it is drawn.
const TPINMIN = Dict(:nmos => (17.0, 12.0), :pmos => (23.0, 12.0),   # (gate, drain/source):
                     :npn => (13.0, 19.0), :pnp => (13.0, 19.0))     # clear of the bubble/bars

tscale(s::Schematic, t::Transistor) = s.scale * t.h / 25           # px per local unit

function pinpx(s::Schematic, t::Transistor, p::Symbol)
    C = px(s, t.at)
    d = px(s, pin(t, p)) - C
    g, v = TPINMIN[t.kind]
    m = (p in (:B, :G) ? g : v) * tscale(s, t)
    L = hypot(d.x, d.y)
    L >= m ? C + d : C + (m / L) * d
end

oscale(s::Schematic, o::Opamp) = s.scale * o.w / 25

# Op-amp geometry: the drawn centre (px) and, in local units from it, the input x, input y
# and output x. The inputs stay where they are placed; when xscale squeezes them closer
# than 20 local units (the triangle's back is at 18) the symbol slides right instead, and
# the output lead reaches at least 2 units past the tip. Inputs stay on the triangle's
# back (|y| ≤ 18).
function opampgeom(s::Schematic, o::Opamp)
    k = oscale(s, o)
    raw = s.scale * s.xscale * o.w / k
    xi = max(raw, 20.0)
    shift = xi - raw
    C = px(s, o.at) + Pt(k * shift, 0)
    C, k, xi, min(s.scale * s.yscale * o.h / k, 18.0), max(raw - shift, 24.0)
end

function pinpx(s::Schematic, o::Opamp, p::Symbol)
    C, k, xi, yi, xo = opampgeom(s, o)
    up = o.inv_up ? p == :inn : p == :inp           # the input on top
    p == :out ? C + Pt(k * xo, 0) : C + Pt(-k * xi, up ? -k * yi : k * yi)
end

# Gate geometry (px). The body keeps its size whatever xscale/yscale do: it is centred on
# the gate, and the input leads (or, for a transmission gate, the a/b leads) run from the
# pins to it. Pins squeezed inside the body by xscale < 1 are drawn just outside it.
const GATE_BUBBLE = 4.0                     # bubble radius, px
function gategeom(s::Schematic, g::Gate)
    C = px(s, g.at)
    k = s.scale
    H = k * gatehalf(g)
    half = k * (g.kind == :tg ? 0.3 : g.w - 0.12)   # half the body width, bubble included
    bub = isinverting(g) ? 2GATE_BUBBLE : 0.0
    x0 = C.x - half                          # body back
    x1 = C.x + half - bub                    # body front (tip)
    C, H, x0, x1
end

function gatepinpx(s::Schematic, g::Gate, p::String)
    C, H, x0, x1 = gategeom(s, g)
    q = px(s, pin(g, p))
    if g.kind == :tg
        p == "a"  && return Pt(min(q.x, x0 - 4), q.y)
        p == "b"  && return Pt(max(q.x, x1 + 4), q.y)
        p == "pg" && return Pt(q.x, min(q.y, C.y - H / 2 - 2GATE_BUBBLE - 4))
        return Pt(q.x, max(q.y, C.y + H / 2 + 4))
    end
    p == "out" && return Pt(max(q.x, x1 + (isinverting(g) ? 2GATE_BUBBLE : 0.0) + 4), q.y)
    Pt(min(q.x, x0 - 4), q.y)
end

# Where each device pin (circuit units) is drawn (px).
function pinmap(s::Schematic)
    m = Dict{Pt,Pt}()
    for it in s.items
        it isa Transistor && for p in (:B, :C, :E)
            m[pin(it, p)] = pinpx(s, it, p)
        end
        it isa Opamp && for p in (:inp, :inn, :out)
            m[pin(it, p)] = pinpx(s, it, p)
        end
        it isa Gate && for p in gatepinnames(it)
            m[pin(it, p)] = gatepinpx(s, it, p)
        end
    end
    m
end
drawn(s::Schematic, ctx, p::Pt) = get(ctx.pins, p, px(s, p))

function render(io, s::Schematic, t::Transistor, _)
    C = px(s, t.at)
    k = tscale(s, t)
    sx = t.xflip ? -k : k
    sy = t.yflip ? -k : k
    g = pinpx(s, t, :B) - C
    v = pinpx(s, t, :C) - C
    print(io, "<g transform=\"translate($(f(C.x)),$(f(C.y))) scale($(f(sx)),$(f(sy)))\" ",
              "stroke-width=\"$(f(1.5 / k))\">",
              tbody(t.kind, -hypot(g.x, g.y) / k, hypot(v.x, v.y) / k), "</g>")
end

function render(io, s::Schematic, o::Opamp, _)
    C, k, xi, y, xo = opampgeom(s, o) # pins in local units (page y points down)
    p, m = o.inv_up ? (y, -y) : (-y, y)          # y of the + and − inputs
    a = min(3.0, 3.5 / k)             # sign half-size: about 3.5 px whatever the scale
    print(io, "<g transform=\"translate($(f(C.x)),$(f(C.y))) scale($(f(k)))\" stroke-width=\"$(f(1.5 / k))\">",
              "<polygon points=\"-18,-22 -18,22 22,0\"/>",
              "<path d=\"M$(f(-xi)),$(f(-y)) H-18 M$(f(-xi)),$(f(y)) H-18 M22,0 H$(f(xo)) ",
              "M$(f(-12 - a)),$(f(p)) h$(f(2a)) M-12,$(f(p - a)) v$(f(2a)) M$(f(-12 - a)),$(f(m)) h$(f(2a))\"/></g>")
end

# x of the back curve of an OR-type body (a quadratic from (x0, y0-H) to (x0, y0+H)
# bulging d to the right) at height y.
function orback(x0, y0, H, d, y)
    t = clamp((y - (y0 - H)) / (2H), 0, 1)
    x0 + 2t * (1 - t) * d
end

function render(io, s::Schematic, g::Gate, _)
    C, H, x0, x1 = gategeom(s, g)
    y0 = C.y
    bw = x1 - x0
    d = 0.25 * bw                                   # OR back-curve control offset
    P(x, y) = "$(f(x)),$(f(y))"
    path = IOBuffer()
    if g.kind == :tg
        a, b = gatepinpx(s, g, "a"), gatepinpx(s, g, "b")
        pg, ng = gatepinpx(s, g, "pg"), gatepinpx(s, g, "ng")
        xm = (x0 + x1) / 2
        r = GATE_BUBBLE
        print(io, "<polygon points=\"", P(x0, y0 - H), " ", P(x1, y0), " ", P(x0, y0 + H), "\"/>",
                  "<polygon points=\"", P(x1, y0 - H), " ", P(x0, y0), " ", P(x1, y0 + H), "\"/>")
        fill = s.background == "none" ? "none" : s.background
        print(io, "<circle cx=\"$(f(xm))\" cy=\"$(f(y0 - H / 2 - r))\" r=\"$(f(r))\" fill=\"$fill\"/>")
        print(io, "<path d=\"M", P(a.x, a.y), " H", f(x0), " M", P(x1, b.y), " H", f(b.x),
                  " M", P(xm, pg.y), " V", f(y0 - H / 2 - 2r), " M", P(xm, ng.y), " V", f(y0 + H / 2), "\"/>")
        return
    end
    ins = [gatepinpx(s, g, p) for p in gatepinnames(g)[1:end-1]]
    out = gatepinpx(s, g, "out")
    orlike = g.kind in (:or, :nor, :xor, :xnor)
    xb = g.kind in (:xor, :xnor) ? x0 + 6 : x0      # the OR body sits behind the XOR's extra curve
    if g.kind in (:inv, :buf)
        print(io, "<polygon points=\"", P(x0, y0 - H), " ", P(x1, y0), " ", P(x0, y0 + H), "\"/>")
    elseif g.kind in (:and, :nand)
        xm = max(x1 - H, x0)
        print(io, "<path d=\"M", P(x0, y0 - H), " H", f(xm), " A", f(x1 - xm), ",", f(H), " 0 0 1 ",
                  P(xm, y0 + H), " H", f(x0), " Z\"/>")
    else
        bwo = x1 - xb
        print(io, "<path d=\"M", P(xb, y0 - H), " Q", P(xb + 0.55bwo, y0 - H), " ", P(x1, y0),
                  " Q", P(xb + 0.55bwo, y0 + H), " ", P(xb, y0 + H),
                  " Q", P(xb + 0.25bwo, y0), " ", P(xb, y0 - H), " Z\"/>")
        if g.kind in (:xor, :xnor)
            print(io, "<path fill=\"none\" d=\"M", P(x0, y0 - H), " Q", P(x0 + 0.25bwo, y0), " ", P(x0, y0 + H), "\"/>")
        end
    end
    if isinverting(g)
        r = GATE_BUBBLE
        fill = s.background == "none" ? "none" : s.background
        print(io, "<circle cx=\"$(f(x1 + r))\" cy=\"$(f(y0))\" r=\"$(f(r))\" fill=\"$fill\"/>")
    end
    tip = x1 + (isinverting(g) ? 2GATE_BUBBLE : 0.0)
    print(path, "M", P(tip, y0), " H", f(out.x))
    bwo = x1 - xb
    for q in ins
        xe = orlike ? orback(x0, y0, H, 0.25bwo, q.y) : x0
        xe > q.x && print(path, " M", P(q.x, q.y), " H", f(xe))
        if abs(q.y - y0) > H                        # a pin beyond the body: extend its back
            print(path, " M", P(x0, y0 + sign(q.y - y0) * H), " V", f(q.y))
        end
    end
    print(io, "<path d=\"", String(take!(path)), "\"/>")
end

function render(io, s::Schematic, w::Wire, ctx)
    pts = map(w.pts) do p
        q = drawn(s, ctx, p isa PinRef ? pin(ctx.devs[p.device], p.pin) : p)
        "$(f(q.x)),$(f(q.y))"
    end
    print(io, "<polyline points=\"", join(pts, " "), "\"/>")
end

function render(io, s::Schematic, g::Ground, _)
    x, y = px(s, g.at).x, px(s, g.at).y
    d = g.flip ? -1 : 1
    print(io, "<path d=\"M$(f(x)),$(f(y)) v$(8d) M$(f(x-10)),$(f(y+8d)) h20 ",
              "M$(f(x-6)),$(f(y+12d)) h12 M$(f(x-2)),$(f(y+16d)) h4\"/>")
end

function render(io, s::Schematic, u::Supply, _)
    C = px(s, u.at)
    print(io, "<path d=\"M$(f(C.x-10)),$(f(C.y)) h20\"/>")
end

function render(io, s::Schematic, p::Port, _)
    C = px(s, p.at)
    fill = s.background == "none" ? "none" : s.background
    print(io, "<circle cx=\"$(f(C.x))\" cy=\"$(f(C.y))\" r=\"3\" fill=\"$fill\"/>")
end

function render(io, s::Schematic, b::Block, _)
    A, B = px(s, b.lo), px(s, b.hi)              # page y points down: B is the top right
    print(io, "<rect x=\"$(f(A.x))\" y=\"$(f(B.y))\" width=\"$(f(B.x - A.x))\" ",
              "height=\"$(f(A.y - B.y))\"/>")
end

render(io, ::Schematic, ::NodeLabel, _) = nothing
render(io, ::Schematic, ::Caption, _) = nothing

function render(io, s::Schematic, d::Dot, _)
    C = px(s, d.at)
    print(io, "<circle cx=\"$(f(C.x))\" cy=\"$(f(C.y))\" r=\"2.6\" fill=\"currentColor\"/>")
end

# ───────────────────────────── document ─────────────────────────────
anchors(::Placed, _) = Pt[]
anchors(b::Bipole, _) = [b.a, b.b]
anchors(t::Transistor, _) = [pin(t, p) for p in (:B, :C, :E)]
anchors(o::Opamp, _) = [[pin(o, p) for p in (:inp, :inn, :out)]; o.at + Pt(0, 0.9 * o.w); o.at - Pt(0, 0.9 * o.w)]
anchors(w::Wire, devs) = [p isa PinRef ? pin(devs[p.device], p.pin) : p for p in w.pts]
anchors(x::Union{Ground,Supply,Port,NodeLabel,Dot,Caption}, _) = [x.at]
anchors(v::Voltage, _) = [v.plus, v.minus]
anchors(c::Current, _) = [c.a, c.b]
anchors(b::Block, _) = [b.lo, b.hi, Pt(b.lo.x, b.hi.y), Pt(b.hi.x, b.lo.y)]
anchors(g::Gate, _) = [[pin(g, p) for p in gatepinnames(g)]; g.at + Pt(0, gatehalf(g)); g.at - Pt(0, gatehalf(g))]

# Bounding box of every point and every text box (text width estimated per character).
function bbox(s::Schematic, devs, boxes)
    xs = Float64[]; ys = Float64[]
    for it in s.items, p in anchors(it, devs)
        q = px(s, p)
        push!(xs, q.x); push!(ys, q.y)
    end
    for t in boxes
        w = (t.style == :note ? 8.0 : t.style == :pin ? 7.0 : 9.0) * t.nchars
        x0 = t.anchor == "start" ? t.at.x : t.anchor == "end" ? t.at.x - w : t.at.x - w / 2
        push!(xs, x0, x0 + w)
        t.base == "middle" ? push!(ys, t.at.y - 9, t.at.y + 9) : push!(ys, t.at.y - 15, t.at.y + 5)
    end
    pad = 20
    minimum(xs) - pad, minimum(ys) - pad, maximum(xs) - minimum(xs) + 2pad, maximum(ys) - minimum(ys) + 2pad
end

const BORDER_W = 3.0                   # border line width, corner radius (px) and colour
const BORDER_R = 10.0
const BORDER_COLOR = "#9a9a9a"

"""
    to_svg(s::Schematic) -> String

The schematic as a standalone SVG document, for saving to a file or embedding in a web
page or a document. Notebooks don't need it: a `Schematic` displays itself as SVG.
"""
function to_svg(s::Schematic)
    isempty(s.items) && return "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"0\" height=\"0\"></svg>"
    devs = Dict{String,Placed}(t.name => t for t in s.items if t isa PinDevice)
    boxes = reduce(vcat, (texts(s, it) for it in s.items); init=TextBox[])
    x, y, w, h = bbox(s, devs, boxes)
    ctx = (devs=devs, pins=pinmap(s))
    io = IOBuffer()
    print(io, "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"$(f(x)) $(f(y)) $(f(w)) $(f(h))\" ",
              "width=\"$(f(w))\" height=\"$(f(h))\" font-family=\"$(s.font)\" font-size=\"15\" ",
              "style=\"color:$(s.stroke)\">")
    # with a border, the background is rounded to match so no square corners show outside it
    s.background == "none" ||
        print(io, "<rect x=\"$(f(x))\" y=\"$(f(y))\" width=\"$(f(w))\" height=\"$(f(h))\" ",
                  s.border ? "rx=\"$(f(BORDER_R + BORDER_W / 2))\" " : "", "fill=\"$(s.background)\"/>")
    if s.border                       # inset by half its width so all of the line shows
        print(io, "<rect x=\"$(f(x + BORDER_W / 2))\" y=\"$(f(y + BORDER_W / 2))\" ",
                  "width=\"$(f(w - BORDER_W))\" height=\"$(f(h - BORDER_W))\" rx=\"$(f(BORDER_R))\" ",
                  "fill=\"none\" stroke=\"$BORDER_COLOR\" stroke-width=\"$(f(BORDER_W))\"/>")
    end
    print(io, "<g fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.5\" ",
              "stroke-linecap=\"round\" stroke-linejoin=\"round\">")
    for it in s.items
        render(io, s, it, ctx)
    end
    for t in boxes
        render(io, s, t)
    end
    print(io, "</g></svg>")
    String(take!(io))
end
