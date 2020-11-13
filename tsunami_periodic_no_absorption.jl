using Pkg
Pkg.activate(".")
Pkg.instantiate()

using CompScienceMeshes
using LinearAlgebra
using SparseArrays

fn = joinpath(@__DIR__, "assets", "accurate_world_20.msh")
border = CompScienceMeshes.read_gmsh_mesh(fn, physical="Border", dimension=1)
coast  = CompScienceMeshes.read_gmsh_mesh(fn, physical="Coast", dimension=1)
sea    = CompScienceMeshes.read_gmsh_mesh(fn, physical="Sea", dimension=2)

# skeleton creates lower dimensional meshes from a given mesh. With second argument
# zero the returned mesh is simply the cloud of vertices on which the original mesh
# was built.
border_vertices = skeleton(border, 0)
coast_vertices  = skeleton(coast, 0)
sea_vertices    = skeleton(sea, 0)

# The FEM as presented here solved the homogenous Dirichlet problem for the Laplace
# equations. This means that we will not be associating basis functions with vertices
# on either boundary. After filtering out these vertices we are left with only
# interior vertices.
interior_vertices = submesh(sea_vertices) do v
    v in coast_vertices && return false
    return true
end

"""
Creates the local to global map for FEM assembly.

    localtoglobal(active_vertices, domain) -> gl

The returned map `gl` can be called as

    gl(k,p)

Here, `k` is an index into `domain` (i.e. it refers to a specific element, and
`p` is a local index into a specific element. It ranges from 1 to 3 for triangular
elements and from 1 to 2 for segments. The function returns an index `i` into
`active_vertices` if the i-th active vertex equals the p-th vertex of element k and
`gl` return `nothing` otherwise.
"""
function localtoglobal(active_vertices, domain)
    conn = copy(transpose(connectivity(active_vertices, domain, abs)))
    nz = nonzeros(conn)
    rv = rowvals(conn)
    function gl(k,p)
        for q in nzrange(conn,k)
            nz[q] == p && return rv[q]
        end
        return nothing
    end
    return gl
end

function elementmatrix(mesh, element)
    v1 = mesh.vertices[element[1]]
    v2 = mesh.vertices[element[2]]
    v3 = mesh.vertices[element[3]]
    tangent1 = v3 - v2
    tangent2 = v1 - v3
    tangent3 = v2 - v1
    normal = (v1-v3) × (v2-v3)
    area = 0.5 * norm(normal)
    normal = normalize(normal)
    grad1 = (normal × tangent1) / (2 *area)
    grad2 = (normal × tangent2) / (2 *area)
    grad3 = (normal × tangent3) / (2 *area)
    k1 = -k^2/6
    k2 = -k^2/12

    S = area * [
        dot(grad1,grad1)+k1 dot(grad1,grad2)+k2 dot(grad1,grad3)+k2
        dot(grad2,grad1)+k2 dot(grad2,grad2)+k1 dot(grad2,grad3)+k2
        dot(grad3,grad1)+k2 dot(grad3,grad2)+k1 dot(grad3,grad3)+k1]
    return S
end

function assemblematrix(mesh, active_vertices)
    n = length(active_vertices)
    S = zeros(n,n)
    gl = localtoglobal(active_vertices, mesh)
    for (k,element) in enumerate(mesh)
        Sel = elementmatrix(mesh, element)
        for p in 1:3
            i = gl_sea(k,p)
            i == nothing && continue
            for q in 1:3
                j = gl_sea(k,q)
                j == nothing && continue
                S[i,j] += Sel[p,q]
            end
        end
    end

    return S
end


function elementvector(f, mesh, element)
    v1 = mesh.vertices[element[1]]
    v2 = mesh.vertices[element[2]]
    v3 = mesh.vertices[element[3]]
    normal = (v1-v3)×(v2-v3)
    area = 0.5*norm(normal)
    #println(area)
    F = area * [
        f(v1)/3
        f(v2)/3
        f(v3)/3]
    #println(F)
    return F
end


function assemblevector(f, mesh, active_vertices)
    n = length(active_vertices)
    F = zeros(n)
    gl = localtoglobal(active_vertices, mesh)
    for (k,element) in enumerate(mesh)
        Fel = elementvector(f,mesh,element)
        for p in 1:3
            i = gl_sea(k,p)
            i == nothing && continue
            F[i] += Fel[p]
            #println(Fel)
        end
    end

    return F
end

# For the assignment of the lab, i.e. the Helmholtz equations (aka the frequency
# domain wave equation), subject to absorbing boundary conditions, you will also
# have to include a term stemming from boundary integral contributions. For that
# term a different local-to-global matrix is required: one linking segments on the
# boundary to indices of active vertices. You can create this map using the same
# function, i.e. like:
#
#   gl = localtoglobal(active_vertices, border)
#

function elementmatrix_boundary(mesh,element)
    v1 = mesh.vertices[element[1]]
    v2 = mesh.vertices[element[2]]
    len = norm(v1-v2)

    T = 0*complex(k*im*len/6*[
        2 1
        1 2
    ])
end


function assemblematrix_boundary(mesh, active_vertices)
    n = length(active_vertices)
    T = complex(zeros(n,n))
    gl = localtoglobal(active_vertices, mesh)
    for (k,element) in enumerate(mesh)
        Sel = elementmatrix_boundary(mesh, element)
        for p in 1:2
            i = gl_boundary(k,p)
            i == nothing && continue
            for q in 1:2
                j = gl_boundary(k,q)
                j == nothing && continue
                T[i,j] += Sel[p,q]
            end
        end
    end

    return T
end


function locate_end_of_world(active_vertices, domain, x_range, y_range)
    gl = localtoglobal(active_vertices, domain)
    cali_coordinates = Dict{String, Array}("lc"=>[], "gc"=>[])
    arctic_coordinates = Dict{String, Array}("lc"=>[], "gc"=>[])
    aus_coordinates = Dict{String, Array}("lc"=>[], "gc"=>[])
    antarctic_coordinates = Dict{String, Array}("lc"=>[], "gc"=>[])

    for (k, element) in enumerate(domain)
        for p in 1:length(element)
            (x, y, z) = border.vertices[element[p]]
            if x == x_range["Left"]
                append!(cali_coordinates["lc"], y)
                append!(cali_coordinates["gc"], gl(k,p))
            end
            if x == x_range["Right"]
                append!(aus_coordinates["lc"], y)
                append!(aus_coordinates["gc"], gl(k,p))
            end
            if y == y_range["Bottom"]
                append!(antarctic_coordinates["lc"], x)
                append!(antarctic_coordinates["gc"], gl(k,p))
            end
            if y == y_range["Top"]
                append!(arctic_coordinates["lc"], x)
                append!(arctic_coordinates["gc"], gl(k,p))
            end
        end
    end

    sorted_sides = Dict{String, Array}(
        "cali" => unique(cali_coordinates["gc"][sortperm(cali_coordinates["lc"])]),
        "aus" => unique(aus_coordinates["gc"][sortperm(aus_coordinates["lc"])]),
        "antarctic" => unique(antarctic_coordinates["gc"][sortperm(antarctic_coordinates["lc"])]),
        "arctic" => unique(arctic_coordinates["gc"][sortperm(arctic_coordinates["lc"])]),
    )
    return sorted_sides
end


function make_periodic(active_vertices, domain, sorted_sides)
    gl = localtoglobal(active_vertices, domain)
    function periodic_gl(k,p)
        index = gl(k,p)
        index in sorted_sides["antarctic"] && return sorted_sides["arctic"][findall(x->x==index, sorted_sides["antarctic"])][1]
        index in sorted_sides["aus"] && return sorted_sides["cali"][findall(x->x==index, sorted_sides["aus"])][1]
        return index
    end
    return periodic_gl
end

function f(x)
    x_0 = [800, -300, 0]
    a = 1
    sigma_squared = 5
    dx = x - x_0
    #println(-(norm(dx)^2)/sigma_squared)
    return a*exp(-(norm(dx)^2)/(2*sigma_squared))
end

k = 2*pi/50

x_range = Dict("Left"=>0, "Right"=>1000)
y_range = Dict("Top"=>0, "Bottom"=>-570)

sorted_sides = locate_end_of_world(interior_vertices, sea, x_range, y_range)
gl_sea = make_periodic(interior_vertices, sea, sorted_sides)
gl_boundary = make_periodic(interior_vertices, border, sorted_sides)

S = complex(assemblematrix(sea, interior_vertices))
F = complex(assemblevector(f, sea, interior_vertices))
T = complex(assemblematrix_boundary(border, interior_vertices))
S_eff = S + T
needed_indices = []
for i in 1:length(interior_vertices)
    i in sorted_sides["antarctic"] && continue
    i in sorted_sides["aus"] && continue
    append!(needed_indices, i)
end
S_eff = S_eff[needed_indices, needed_indices]
#println(S_eff)
F = F[needed_indices]
u = S_eff \ F

#println(F)

u_new = complex(zeros(length(interior_vertices)))

for (i, index) in enumerate(needed_indices)
    u_new[index] = u[i]
end
for i in 1:length(sorted_sides["antarctic"])
    u_new[sorted_sides["antarctic"][i]] = u_new[sorted_sides["arctic"][i]]
end
for i in 1:length(sorted_sides["aus"])
    u_new[sorted_sides["aus"][i]] = u_new[sorted_sides["cali"][i]]
end

u_tilda = complex(zeros(length(sea_vertices)))
for (j,m) in enumerate(interior_vertices)
    u_tilda[m[1]] = u_new[j]
end

using Makie
scene = Makie.mesh(vertexarray(sea), cellarray(sea), color=real(u_tilda))

clr = colorlegend(
    scene[end],
    raw = true,
    camera = campixel!,

    width = (
        30,
        560
    )
)

plot = vbox(scene, clr)
