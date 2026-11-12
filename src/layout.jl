# ───────────────────── combining drawings into one figure ─────────────────────

"""
    layout(parts...; direction=:row, gap=1.5, align=nothing, connect=[], share=[],
           nodelabels=false, compact=true, rails=true, kw...) -> Schematic

Place drawings side by side (`direction=:row`, left to right) or stacked
(`direction=:column`, top to bottom) in one figure, `gap` circuit units apart. A part is
a `Schematic` (for instance one annotated with its own values) or an ASCII drawing,
which is parsed with `ascii_schematic`. The result is an ordinary `Schematic`: it can be
annotated, netlisted, turned into a subcircuit or laid out again.

Parts can be joined at their terminals in two ways, which can be mixed:

- `connect=[(1, "out") => (2, "in")]` draws the connection: the second part is shifted so
  the two terminals line up and a wire joins them, replacing both terminal circles. The
  parts must be neighbours, and each neighbouring pair can have one drawn connection.
- `share=[(1, "out") => (2, "in")]` connects by name only: both terminals (or node tags)
  stay drawn and take one name, so their labels match. A plain name, `share=["vb"]`,
  makes that node common to every part that has it.

Supplies and ground are always common. Any other element or node name used in more than
one part gets the part's number as a suffix in the result (`CC1` → `CC1_1`, `CC1_2`;
`@g` → `g_1`, `g_2`), so separate parts stay separate. The joined node of a drawn
connection keeps the first terminal's name (with the part suffix if that name is used
elsewhere), and so does a shared pair. Drawn labels of elements are unchanged; terminal
and node labels that show their node name follow the renaming.

`nodelabels=true` labels the nodes of the combined circuit with their netlist names, as
[`label_nodes`](@ref) does (`:all` also labels ground and supplies). Label the result
rather than the parts: a part's labels become node names, numbered like any other name.

In a row, every part's top supplies (V_DD, V_CC) line up at the top of the figure and its
bottom supplies (V_SS, V_EE) at the bottom, by lengthening the vertical wires that lead to
them (`rails=false` turns this off). Before placing the parts, long runs of vertical wire
are shortened to one row (`compact=false` keeps them): only stretches where nothing but
vertical wires cross, so components keep their spacing. Wires of a drawn connection stay
straight; a supply that can't move without bending one stays where it is.

`align` sets how parts not joined by a drawn connection line up: `:top` (the default for
a row), `:center` or `:bottom`; for a column `:left` (the default), `:center` or `:right`.
Other keywords are settings of the result (`xscale`, `border`, …), which otherwise come
from the first part.

`[s1 s2]` and `[s1; s2]` lay out `Schematic`s in a row or a column with the defaults.
"""
function layout(parts...; direction::Symbol=:row, gap::Real=1.5, align=nothing,
                connect=(), share=(), nodelabels=false, compact::Bool=true, rails::Bool=true, kw...)
    direction in (:row, :column) ||
        throw(ArgumentError("direction must be :row or :column, got $(repr(direction))"))
    isempty(parts) && throw(ArgumentError("layout needs at least one part"))
    row = direction == :row
    align = something(align, row ? :top : :left)
    align in (row ? (:top, :center, :bottom) : (:left, :center, :right)) ||
        throw(ArgumentError("align=$(repr(align)) doesn't apply to a $direction"))
    ss = Schematic[p isa Schematic ? p : ascii_schematic(String(p)) for p in parts]
    compact && (ss = Schematic[compacted(x) for x in ss])
    np = length(ss)
    checkpart(k) = 1 <= k <= np || throw(ArgumentError("there is no part $k (parts 1–$np)"))

    # Node names (lowercase) used by each part's terminals and node tags.
    nodenames = [Set(lowercase(it.name) for it in s.items
                     if it isa Union{Port,NodeLabel} && !isempty(it.name)) for s in ss]
    hasport(k, n) = any(it -> it isa Port && lowercase(it.name) == lowercase(n), ss[k].items)

    # 1. Shared and joined nodes: renames per part, and names that are common on purpose.
    nren = [Dict{String,String}() for _ in 1:np]
    common = Set{String}()
    # one node from terminal `a` of part i and `b` of part j: it keeps a's name, with i's
    # suffix when that name is used elsewhere
    function join!(i, a, j, b)
        a, b = String(a), String(b)
        elsewhere = any(m -> lowercase(a) in nodenames[m] && !(m == i) &&
                             !(m == j && lowercase(a) == lowercase(b)), 1:np)
        joined = elsewhere ? "$(a)_$i" : a
        nren[i][lowercase(a)] = joined
        nren[j][lowercase(b)] = joined
        push!(common, lowercase(joined))
        joined
    end
    joins = Dict{Int,Tuple{String,String,String}}()          # k => (name in k, name in k+1, joined)
    for c in connect
        (i, a), (j, b) = first(c), last(c)
        checkpart(i); checkpart(j)
        abs(i - j) == 1 || throw(ArgumentError(
            "connect: parts $i and $j are not neighbours; use share=[($i, \"$a\") => ($j, \"$b\")]"))
        if i > j                                         # left / upper part first
            i, a, j, b = j, b, i, a
        end
        haskey(joins, i) && throw(ArgumentError(
            "connect: parts $i and $j already have a drawn connection; use share for more"))
        for (k, n) in ((i, a), (j, b))
            hasport(k, n) || throw(ArgumentError("connect: part $k has no terminal '$n'"))
        end
        joins[i] = (String(a), String(b), join!(i, a, j, b))
    end
    for c in share
        if c isa Pair
            (i, a), (j, b) = first(c), last(c)
            checkpart(i); checkpart(j)
            i == j && throw(ArgumentError("share: both nodes are in part $i"))
            for (k, n) in ((i, a), (j, b))
                lowercase(n) in nodenames[k] || throw(ArgumentError("share: part $k has no node '$n'"))
            end
            join!(i, a, j, b)
        else
            push!(common, lowercase(string(c)))
        end
    end

    # 2. Names used by more than one part get the part number, unless common.
    renamed(k, n) = get(nren[k], lowercase(n), n)
    users = Dict{String,Set{Int}}()
    for k in 1:np, n in nodenames[k]
        push!(get!(users, lowercase(renamed(k, n)), Set{Int}()), k)
    end
    nodeclash = Set(n for (n, ks) in users if length(ks) > 1 && !(n in common))
    function nname(k, n)
        isempty(n) && return n
        m = renamed(k, n)
        lowercase(m) in nodeclash ? "$(m)_$k" : m
    end
    elems = Dict{String,Set{Int}}()
    for k in 1:np, it in ss[k].items
        it isa Union{Bipole,Transistor,Opamp} && !isempty(it.name) &&
            push!(get!(elems, uppercase(it.name), Set{Int}()), k)
    end
    elemclash = Set(n for (n, ks) in elems if length(ks) > 1)
    ename(k, n) = uppercase(n) in elemclash ? "$(n)_$k" : n

    # 3. Placement: each part next to the previous one.
    boxes = map(ss) do s
        devs = Dict{String,Placed}(t.name => t for t in s.items if t isa Union{Transistor,Opamp})
        pts = reduce(vcat, (anchors(it, devs) for it in s.items); init=Pt[])
        isempty(pts) ? (0.0, 0.0, 0.0, 0.0) :
            (minimum(p.x for p in pts), maximum(p.x for p in pts),
             minimum(p.y for p in pts), maximum(p.y for p in pts))
    end
    # the terminal circle of a drawn connection: the one facing the other part
    function facing(k, n, leading)
        ps = [it for it in ss[k].items if it isa Port && lowercase(it.name) == lowercase(n)]
        key = row ? (p -> p.at.x) : (p -> -p.at.y)
        leading ? argmax(key, ps) : argmin(key, ps)
    end
    offs = [Pt(0, 0)]
    removed = [Port[] for _ in 1:np]
    extra = Placed[]
    for k in 2:np
        (l0, r0, b0, t0), (l, r, b, t) = boxes[k-1], boxes[k]
        d0 = offs[k-1]
        along = row ? r0 + d0.x + gap - l : b0 + d0.y - gap - t
        if haskey(joins, k - 1)
            a, bname, joined = joins[k-1]
            pa, pb = facing(k - 1, a, true), facing(k, bname, false)
            across = row ? pa.at.y + d0.y - pb.at.y : pa.at.x + d0.x - pb.at.x
            push!(removed[k-1], pa); push!(removed[k], pb)
            d = row ? Pt(along, across) : Pt(across, along)
            A, B = pa.at + d0, pb.at + d
            push!(extra, Wire(A, B), NodeLabel(A, joined, :above; label=""))
        else
            across = row ? (align == :top ? t0 + d0.y - t : align == :bottom ? b0 + d0.y - b :
                            (b0 + t0) / 2 + d0.y - (b + t) / 2) :
                           (align == :left ? l0 + d0.x - l : align == :right ? r0 + d0.x - r :
                            (l0 + r0) / 2 + d0.x - (l + r) / 2)
            d = row ? Pt(along, across) : Pt(across, along)
        end
        push!(offs, d)
    end

    # 4. Supply rails (rows): every part's top supplies (V_DD, …) move up to the top of
    # the figure and its bottom supplies (V_SS, …) down to the bottom, by stretching a
    # band of vertical wires; drawn connections stay where they are.
    fys = Any[identity for _ in 1:np]
    if rails && row && np > 1
        ytop = maximum(boxes[k][4] + offs[k].y for k in 1:np)
        ybot = minimum(boxes[k][3] + offs[k].y for k in 1:np)
        for k in 1:np
            tops = [it.at.y for it in ss[k].items if it isa Supply && it.up]
            bots = [it.at.y for it in ss[k].items if it isa Supply && !it.up]
            up = isempty(tops) ? 0.0 : ytop - (maximum(tops) + offs[k].y)
            down = isempty(bots) ? 0.0 : (minimum(bots) + offs[k].y) - ybot
            fys[k] = railmap(ss[k], up, down, [p.at.y for p in removed[k]])
        end
    end

    # 5. The combined drawing.
    items = Placed[]
    values = Dict{String,Any}()
    for k in 1:np
        for it in ss[k].items
            any(p -> p === it, removed[k]) && continue
            push!(items, relocate(it, offs[k], n -> ename(k, n), n -> nname(k, n); fy=fys[k]))
        end
        for (key, v) in ss[k].values
            values[uppercase(ename(k, key))] = v
        end
    end
    append!(items, extra)
    withnodelabels(Schematic(ss[1]; items, values, kw...), nodelabels)
end

# A copy of `it` moved by `d`, with element names renamed by `ename` (also in PinRefs) and
# node names by `nname` (and labels that show the node name).
# `fy` remaps heights first (compacting, supply rails); then the item moves by `d`.
function relocate(it::T, d::Pt, ename, nname; fy=identity) where {T<:Placed}
    mv(p) = Pt(p.x, fy(p.y)) + d
    vals = Any[]
    for f in fieldnames(T)
        v = getfield(it, f)
        if v isa Pt
            v = mv(v)
        elseif v isa Vector{WirePt}
            v = WirePt[p isa Pt ? mv(p) : PinRef(ename(p.device), p.pin) for p in v]
        end
        push!(vals, v)
    end
    x = T(vals...)
    if x isa Union{Bipole,Transistor,Opamp}
        x = withfields(x; name=ename(x.name))
    elseif x isa Union{Port,NodeLabel}
        new = nname(x.name)
        label = !isempty(x.name) && lowercase(x.label) == lowercase(x.name) ? new : x.label
        x = withfields(x; name=new, label)
    end
    x
end

# ─────────────── bands: compacting and supply rails ───────────────
# A drawing is cut into horizontal bands at every height where something sits (a wire
# corner, a pin, a symbol end, a label point). A band is elastic when only vertical wires
# cross it: no symbol, slanted wire or voltage mark spans it. Elastic bands can shrink or
# grow without changing anything else in the drawing.
const MINBAND = 0.8          # a compacted elastic band keeps one ASCII row (circuit units)
const YTOL = 1e-6

function bands(s::Schematic)
    devs = Dict{String,Placed}(t.name => t for t in s.items if t isa Union{Transistor,Opamp})
    rp(p) = p isa PinRef ? pin(devs[p.device], p.pin) : p
    # Heights where something sits. A point where a vertical wire only passes through
    # (wire above and below it, nothing else there) doesn't count: ASCII drawings draw a
    # vertical run as one short wire per row.
    key(p) = (round(p.x; digits=6), round(p.y; digits=6))
    through = Dict{Tuple{Float64,Float64},Vector{Bool}}()   # point => [wire above, wire below, other]
    mark!(p, i) = (get!(through, key(p), [false, false, false])[i] = true)
    for it in s.items
        if it isa Wire
            ps = map(rp, it.pts)
            for (i, p) in enumerate(ps)
                prev = i > 1 ? ps[i-1] : nothing
                nxt = i < length(ps) ? ps[i+1] : nothing
                vert(q) = q !== nothing && abs(q.x - p.x) <= YTOL && abs(q.y - p.y) > YTOL
                for q in (prev, nxt)
                    q === nothing && continue
                    vert(q) ? mark!(p, q.y > p.y ? 1 : 2) : mark!(p, 3)
                end
                length(ps) == 1 && mark!(p, 3)
            end
        else
            foreach(p -> mark!(p, 3), anchors(it, devs))
        end
    end
    ys = [k[2] for (k, (above, below, other)) in through if !(above && below && !other)]
    spans = Tuple{Float64,Float64}[]                 # heights nothing may stretch inside
    for it in s.items
        if it isa Bipole && it.kind != :short
            push!(spans, minmax(it.a.y, it.b.y))
        elseif it isa Transistor
            push!(spans, (it.at.y - it.h, it.at.y + it.h))
        elseif it isa Opamp
            e = max(it.h, 0.9 * it.w)
            push!(spans, (it.at.y - e, it.at.y + e))
        elseif it isa Voltage
            push!(spans, minmax(it.plus.y, it.minus.y))
        elseif it isa Wire
            ps = map(rp, it.pts)
            for i in 1:length(ps)-1
                a, b = ps[i], ps[i+1]
                abs(a.x - b.x) > YTOL && abs(a.y - b.y) > YTOL && push!(spans, minmax(a.y, b.y))
            end
        end
    end
    sort!(unique!(ys))
    elastic = [!any(((lo, hi),) -> lo <= ys[k] + YTOL && hi >= ys[k+1] - YTOL, spans)
               for k in 1:length(ys)-1]
    ys, elastic
end

# Height map that shrinks every elastic band taller than MINBAND to MINBAND, keeping the
# lowest point where it is.
function compactmap(s::Schematic)
    ys, elastic = bands(s)
    length(ys) < 2 && return identity
    any(k -> elastic[k] && ys[k+1] - ys[k] > MINBAND + YTOL, 1:length(ys)-1) || return identity
    ny = copy(ys)
    for k in 1:length(ys)-1
        g = ys[k+1] - ys[k]
        ny[k+1] = ny[k] + (elastic[k] ? min(g, MINBAND) : g)
    end
    function (y)
        y <= ys[1] && return y
        y >= ys[end] && return y + ny[end] - ys[end]
        k = searchsortedlast(ys, y)
        ny[k] + (y - ys[k]) / (ys[k+1] - ys[k]) * (ny[k+1] - ny[k])
    end
end

compacted(s::Schematic) =
    (f = compactmap(s); Schematic(s; items=Placed[relocate(it, Pt(0, 0), identity, identity; fy=f) for it in s.items]))

# Height map that raises a part's top supplies by `up` and lowers its bottom supplies by
# `down`, by stretching the elastic band just below the top supplies (above every fixed
# height, e.g. a drawn connection's terminal) and the one just above the bottom supplies
# (below every fixed height). A move with no such band is skipped.
function railmap(s::Schematic, up, down, fixed)
    ys, elastic = bands(s)
    tops = [it.at.y for it in s.items if it isa Supply && it.up]
    bots = [it.at.y for it in s.items if it isa Supply && !it.up]
    hi, lo = isempty(fixed) ? (-Inf, Inf) : (maximum(fixed), minimum(fixed))
    cut_up = cut_down = nothing
    if up > YTOL && !isempty(tops)
        j = findlast(k -> elastic[k] && ys[k] >= hi - YTOL && ys[k+1] <= minimum(tops) + YTOL,
                     1:length(ys)-1)
        j === nothing || (cut_up = ys[j+1])
    end
    if down > YTOL && !isempty(bots)
        j = findfirst(k -> elastic[k] && ys[k+1] <= lo + YTOL && ys[k] >= maximum(bots) - YTOL,
                      1:length(ys)-1)
        j === nothing || (cut_down = ys[j])
    end
    y -> y + (cut_up !== nothing && y >= cut_up - YTOL ? up : 0.0) -
             (cut_down !== nothing && y <= cut_down + YTOL ? down : 0.0)
end

withfields(it::T; kw...) where {T} =
    T((haskey(kw, f) ? kw[f] : getfield(it, f) for f in fieldnames(T))...)

Base.hcat(s::Schematic, rest::Schematic...) = layout(s, rest...; direction=:row)
Base.vcat(s::Schematic, rest::Schematic...) = layout(s, rest...; direction=:column)
