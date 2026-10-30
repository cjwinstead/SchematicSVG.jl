# ──────────────────────────── container ─────────────────────────────
Base.@kwdef struct Schematic
    items::Vector{Placed} = Placed[]
    scale::Float64 = 50.0        # px per circuit unit
    stroke::String = "#222"
    background::String = "white" # "none" for transparent
    font::String = "serif"
    values::Dict{String,Any} = Dict{String,Any}()   # raw element values/objects, by NAME
end
Schematic(items::AbstractVector; kw...) = Schematic(; items=collect(Placed, items), kw...)

Base.show(io::IO, ::MIME"image/svg+xml", s::Schematic) = print(io, to_svg(s))

# ─────────────────────────── SVG backend ────────────────────────────
f(x) = string(round(x; digits=2))

xmlesc(s) = replace(s, "&" => "&amp;", "<" => "&lt;", ">" => "&gt;", "\"" => "&quot;")

px(s::Schematic, p::Pt) = Pt(s.scale * p.x, -s.scale * p.y)

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
    _, hh, _ = body(b.kind)
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
    k = s.scale * o.w / 25
    C = px(s, o.at)
    out = TextBox[]
    isempty(o.label) || push!(out, TextBox(C + Pt(4k, -20k), "start", "auto", texlabel(o.label), :label))
    isempty(o.note)  || push!(out, TextBox(C + Pt(4k, 20k + 12), "start", "auto", notetext(o.note), :note))
    out
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

# Node names sit just off the wire; above/below they start a little to the right of the
# point so a vertical wire through it doesn't strike through the text.
function texts(s::Schematic, n::NodeLabel)
    off, anchor, base = n.side == :above ? (Pt(5, -6), "start", "auto") :
                        n.side == :below ? (Pt(5, 16), "start", "auto") : SIDE[n.side]
    [TextBox(px(s, n.at) + off, anchor, base, texlabel(n.label), :node)]
end

function render(io, ::Schematic, t::TextBox)
    style = t.style == :node ? " font-style=\"italic\"" : t.style == :note ? " font-size=\"13\"" : ""
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

function render(io, s::Schematic, b::Bipole, _)
    A, B = px(s, b.a), px(s, b.b)
    d = B - A
    L = hypot(d.x, d.y)
    θ = atan(d.y, d.x) * 180 / π
    hw, _, svg = body(b.kind)
    m = L / 2
    if b.kind != :open
        print(io, "<g transform=\"translate($(f(A.x)),$(f(A.y))) rotate($(f(θ)))\">",
                  "<line x1=\"0\" y1=\"0\" x2=\"$(f(m - hw))\" y2=\"0\"/>",
                  "<line x1=\"$(f(m + hw))\" y1=\"0\" x2=\"$(f(L))\" y2=\"0\"/>",
                  "<g transform=\"translate($(f(m)),0)\">", svg, "</g></g>")
    end
    if b.kind == :sV                    # upright sine wave, whatever the direction
        c = 0.5 * (A + B)
        print(io, "<path d=\"M$(f(c.x - 9)),$(f(c.y)) q4.5,-9 9,0 t9,0\"/>")
    end
    if haskey(SIGNS, b.kind)
        off, h = SIGNS[b.kind]
        u = (1 / L) * d
        p = A + (m - off) * u              # '+' near a (the n+ terminal)
        q = A + (m + off) * u
        print(io, "<path d=\"M$(f(p.x - h)),$(f(p.y)) h$(f(2h)) M$(f(p.x)),$(f(p.y - h)) v$(f(2h)) ",
                  "M$(f(q.x - h)),$(f(q.y)) h$(f(2h))\"/>")
    end
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
function tbody(kind::Symbol, gx=-25)
    if kind in (:npn, :pnp)
        s = "<circle cx=\"-4\" cy=\"0\" r=\"17\"/>" *
            "<path d=\"M$(f(gx)),0 H-10 M-10,-12 V12 M-10,-5 L0,-15 V-25 M-10,5 L0,15 V25\"/>"
        dir = Pt(10, 10)
        s *= kind == :npn ? arrowhead(Pt(-2, 13), dir) : arrowhead(Pt(-8, 7), -1 * dir)
        return s
    else # :nmos, :pmos
        ge = kind == :pmos ? -20 : -14
        s = "<path d=\"M$(f(gx)),0 H$ge M-14,-10 V10 M-10,-13 V13 M-10,-8 H0 V-25 M-10,8 H0 V25\"/>"
        kind == :pmos && (s *= "<circle cx=\"-17\" cy=\"0\" r=\"3\"/>")
        s *= kind == :nmos ? arrowhead(Pt(-2, 8), Pt(1, 0)) : arrowhead(Pt(-8, 8), Pt(-1, 0))
        return s
    end
end

function render(io, s::Schematic, t::Transistor, _)
    C = px(s, t.at)
    k = s.scale * t.h / 25             # pins land exactly on pin(t, ...)
    sx = t.xflip ? -k : k
    sy = t.yflip ? -k : k
    print(io, "<g transform=\"translate($(f(C.x)),$(f(C.y))) scale($(f(sx)),$(f(sy)))\" ",
              "stroke-width=\"$(f(1.5 / k))\">", tbody(t.kind, -25 * t.w / t.h), "</g>")
end

function render(io, s::Schematic, o::Opamp, _)
    C = px(s, o.at)
    k = s.scale * o.w / 25            # pins land exactly on pin(o, ...)
    y = 25 * o.h / o.w                # input offset in local units (page y points down)
    p, m = o.inv_up ? (y, -y) : (-y, y)          # y of the + and − inputs
    a = min(3.0, 3.5 / k)             # sign half-size: about 3.5 px whatever the scale
    print(io, "<g transform=\"translate($(f(C.x)),$(f(C.y))) scale($(f(k)))\" stroke-width=\"$(f(1.5 / k))\">",
              "<polygon points=\"-18,-22 -18,22 22,0\"/>",
              "<path d=\"M-25,$(f(-y)) H-18 M-25,$(f(y)) H-18 M22,0 H25 ",
              "M$(f(-12 - a)),$(f(p)) h$(f(2a)) M-12,$(f(p - a)) v$(f(2a)) M$(f(-12 - a)),$(f(m)) h$(f(2a))\"/></g>")
end

function render(io, s::Schematic, w::Wire, devs)
    pts = map(w.pts) do p
        q = px(s, p isa PinRef ? pin(devs[p.device], p.pin) : p)
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

render(io, ::Schematic, ::NodeLabel, _) = nothing

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
anchors(x::Union{Ground,Supply,Port,NodeLabel,Dot}, _) = [x.at]

# Bounding box of every point and every text box (text width estimated per character).
function bbox(s::Schematic, devs, boxes)
    xs = Float64[]; ys = Float64[]
    for it in s.items, p in anchors(it, devs)
        q = px(s, p)
        push!(xs, q.x); push!(ys, q.y)
    end
    for t in boxes
        w = (t.style == :note ? 8.0 : 9.0) * t.nchars
        x0 = t.anchor == "start" ? t.at.x : t.anchor == "end" ? t.at.x - w : t.at.x - w / 2
        push!(xs, x0, x0 + w)
        t.base == "middle" ? push!(ys, t.at.y - 9, t.at.y + 9) : push!(ys, t.at.y - 15, t.at.y + 5)
    end
    pad = 20
    minimum(xs) - pad, minimum(ys) - pad, maximum(xs) - minimum(xs) + 2pad, maximum(ys) - minimum(ys) + 2pad
end

function to_svg(s::Schematic)
    isempty(s.items) && return "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"0\" height=\"0\"></svg>"
    devs = Dict{String,Placed}(t.name => t for t in s.items if t isa Union{Transistor,Opamp})
    boxes = reduce(vcat, (texts(s, it) for it in s.items); init=TextBox[])
    x, y, w, h = bbox(s, devs, boxes)
    io = IOBuffer()
    print(io, "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"$(f(x)) $(f(y)) $(f(w)) $(f(h))\" ",
              "width=\"$(f(w))\" height=\"$(f(h))\" font-family=\"$(s.font)\" font-size=\"15\" ",
              "style=\"color:$(s.stroke)\">")
    s.background == "none" ||
        print(io, "<rect x=\"$(f(x))\" y=\"$(f(y))\" width=\"$(f(w))\" height=\"$(f(h))\" fill=\"$(s.background)\"/>")
    print(io, "<g fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.5\" ",
              "stroke-linecap=\"round\" stroke-linejoin=\"round\">")
    for it in s.items
        render(io, s, it, devs)
    end
    for t in boxes
        render(io, s, t)
    end
    print(io, "</g></svg>")
    String(take!(io))
end
