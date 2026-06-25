------------------//SERVICES
local ReplicatedFirst: ReplicatedFirst = game:GetService("ReplicatedFirst")

------------------//CONSTANTS
local Packages = ReplicatedFirst:WaitForChild("Packages")
local ExpressivePrompts = Packages:WaitForChild("ExpressivePrompts")
local ExpressivePackages = ExpressivePrompts:WaitForChild("Packages")
local PackageIndex = ExpressivePackages:WaitForChild("_Index")
local SeamPackage = PackageIndex:WaitForChild("miagobble_seam@0.5.1")
local Seam = SeamPackage:WaitForChild("seam")
local Modules = Seam:WaitForChild("Modules")

------------------//VARIABLES
local Trove = require(Modules:WaitForChild("Trove"))

------------------//FUNCTIONS

------------------//MAIN FUNCTIONS

------------------//INIT
return Trove
