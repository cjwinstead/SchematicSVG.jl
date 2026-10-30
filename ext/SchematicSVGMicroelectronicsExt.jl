"""
Loaded automatically when both SchematicSVG and Microelectronics are in use: turns a
drawn schematic into Microelectronics.jl element objects.
"""
module SchematicSVGMicroelectronicsExt

using SchematicSVG
using SchematicSVG: NetDevice, SchematicNetlist, DEFAULT_MODEL, spicename, rawvalue, controlspec,
                    subcircuit_netlist
import SchematicSVG: to_microelectronics, to_subcircuit, objectline, annotation, valuetext, instancename
import Microelectronics as ME

# ─────────────── annotations from Microelectronics objects ───────────────
# Components already have `name` and `value`/`model` fields; these cover the rest.

# Dependent sources keep their name without the letter (VCCS(name="1") prints as G1).
const DEP_LETTER = Dict(ME.VCVS => 'E', ME.VCCS => 'G', ME.CCVS => 'H', ME.CCCS => 'F')
function instancename(x::ME.DependentSource)
    L = DEP_LETTER[typeof(x)]
    !isempty(x.name) && uppercase(x.name[1]) == L ? x.name : string(L, x.name)
end

annotation(s::ME.Source) = s.waveforms
annotation(x::ME.DependentSource) = x.gain
valuetext(w::AbstractVector{<:ME.Waveform}, name) = join((strip(sprint(print, x)) for x in w), ", ")

# ─────────────── objects the user supplied: keep them, rewire them ───────────────

function rebuild(c::ME.Component, d::NetDevice)
    nodes = copy(d.nodes)
    if d.kind in (:nmos, :pmos) && length(c.nodes) == 4
        # A body given apart from the source is kept (e.g. "vdd", "0"); one tied to the
        # source follows the drawn source.
        push!(nodes, c.nodes[4] == c.nodes[3] ? d.nodes[3] : c.nodes[4])
    end
    length(nodes) == length(c.nodes) || throw(ArgumentError(
        "$(c.name) has $(length(c.nodes)) terminals but the drawing gives it $(length(nodes))"))
    ME.Component(c.name, c.species, c.prefix, nodes, c.value, c.model, copy(c.parameters))
end

function rebuild(s::ME.Source, d::NetDevice)
    length(d.nodes) == 2 || throw(ArgumentError("$(s.name) is a source but is drawn as a $(d.kind)"))
    ME.Source(s.name, s.species, s.prefix, copy(d.nodes), s.waveforms)
end

rebuild(x::T, d::NetDevice) where {T<:ME.DependentSource} =
    T(x.name, d.nodes[1], d.nodes[2], x.control, x.gain)

objectline(x::ME.Element, d::NetDevice) = strip(string(rebuild(x, d)))

# ─────────────── devices built from values ───────────────

placeholder(nm) = Symbol(nm)                 # written as {name}: define it with .param

function rawsource(nm, U, nodes, text)
    ME.Component(; name=nm, species=lowercase(U) * "source", prefix=U, nodes=copy(nodes), value=String(text))
end

function medevice(d::NetDevice)
    x = d.value
    x isa ME.Element && return rebuild(x, d)
    k, nm, n = d.kind, d.name, d.nodes
    v = rawvalue(x)
    if k == :R
        return ME.Resistor(nm, n[1], n[2], something(v, placeholder(nm)))
    elseif k == :C
        return ME.Capacitor(nm, n[1], n[2], something(v, placeholder(nm)))
    elseif k == :L
        return ME.Inductor(nm, n[1], n[2], something(v, placeholder(nm)))
    elseif k == :D
        return ME.Diode(nm, n[1], n[2], v isa AbstractString ? String(v) : DEFAULT_MODEL[:D])
    elseif k in (:V, :I)
        U = k == :V ? "V" : "I"
        name = spicename(nm, U[1])
        v isa AbstractString && return rawsource(name, U, n, v)
        v isa ME.Waveform && return ME.Source(name, lowercase(U) * "source", U, copy(n), [v])
        if v isa AbstractVector && !isempty(v) && all(w -> w isa ME.Waveform, v)
            return ME.Source(name, lowercase(U) * "source", U, copy(n), collect(ME.Waveform, v))
        end
        return (k == :V ? ME.Vdc : ME.Idc)(name, n[1], n[2], something(v, placeholder(name)))
    elseif k in (:sV, :sI)
        U = k == :sV ? "V" : "I"
        f = k == :sV ? ME.Vsin : ME.Isin
        name = spicename(nm, U[1])
        v isa AbstractString && return rawsource(name, U, n, v)
        v isa NamedTuple && return f(name, n[1], n[2]; v...)
        v === nothing && return f(name, n[1], n[2])
        return f(name, n[1], n[2]; amplitude=v)
    elseif k in (:E, :F, :G, :H)
        gain, ctrl = controlspec(x)
        letter = first(string(k))
        base = uppercase(nm[1]) == letter ? String(nm[nextind(nm, 1):end]) : String(nm)
        k == :E && return ME.VCVS(; name=base, nplus=n[1], nminus=n[2], control=string.(collect(ctrl)), gain)
        k == :G && return ME.VCCS(; name=base, nplus=n[1], nminus=n[2], control=string.(collect(ctrl)), gain)
        k == :H && return ME.CCVS(; name=base, nplus=n[1], nminus=n[2], control=string(ctrl), gain)
        return ME.CCCS(; name=base, nplus=n[1], nminus=n[2], control=string(ctrl), gain)
    elseif k in (:nmos, :pmos)
        f = k == :nmos ? ME.NMOS : ME.PMOS
        v isa AbstractString && return f(nm, n...; model=String(v))
        if v isa NamedTuple
            haskey(v, :body) || return f(nm, n...; v...)
            rest = Base.structdiff(v, NamedTuple{(:body,)})
            return f(nm, n..., string(v.body); rest...)
        end
        return f(nm, n...)
    elseif k in (:npn, :pnp)
        return ME.Component(; name=nm, species="bjt", prefix="Q", nodes=copy(n),
                            model=v isa AbstractString ? String(v) : DEFAULT_MODEL[k])
    else                                                         # :opamp
        return ME.Opamp(nm, n[1], n[2], n[3], v isa AbstractString ? String(v) : DEFAULT_MODEL[:opamp])
    end
end

issource(x) = x isa ME.Source || (x isa ME.Component && x.prefix in ("V", "I"))

function to_microelectronics(n::SchematicNetlist)
    sources = ME.Element[]
    components = ME.Element[]
    for (net, v) in n.supplies
        nm = spicename(uppercase(net), 'V')
        push!(sources, ME.Vdc(nm, net, 0, something(v, placeholder(nm))))
    end
    for d in n.devices
        x = medevice(d)
        push!(issource(x) ? sources : components, x)
    end
    (; sources, components)
end

to_microelectronics(s::SchematicSVG.Schematic; kw...) = to_microelectronics(schematic_netlist(s; kw...))

asparameter(p::ME.Parameter) = p
asparameter(p::Pair) = ME.Parameter(string(first(p)), last(p))

function to_subcircuit(s::SchematicSVG.Schematic; name, terminals, parameters=ME.Parameter[],
                       rename=Dict(), elements=())
    n = subcircuit_netlist(s, terminals; rename, elements)
    renames = Dict(lowercase(string(k)) => string(v) for (k, v) in rename)
    ME.Subcircuit(; name=string(name),
                  terminals=[get(renames, lowercase(string(t)), string(t)) for t in terminals],
                  parameters=ME.Parameter[asparameter(p) for p in parameters],
                  components=ME.Element[medevice(d) for d in n.devices])
end

end # module
