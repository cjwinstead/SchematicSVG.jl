# Loaded when Unitful is in use: SPICE text gets plain numbers in SI units for quantities
# (`4.7u"kΩ"` → `4700`, `10u"μF"` → `1.0e-5`) instead of Unitful's display form.
# With Microelectronics.jl loaded, its own `qstr` formatting is used instead.
# (A comment, not a docstring: a docstring on an extension module can fail to load.)
module SchematicSVGUnitfulExt

import SchematicSVG: spicevalue
using Unitful: AbstractQuantity, ustrip, upreferred

spicevalue(q::AbstractQuantity) = spicevalue(Float64(ustrip(upreferred(q))))

end # module
