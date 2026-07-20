-- Compatibility adapter for older Studio references.
-- New HUD code should require HorseViewportRenderer directly.

local HorseViewportRenderer = require(script.Parent:WaitForChild("HorseViewportRenderer"))

local HorseIndexViewportCache = {}

function HorseIndexViewportCache.Get(catalogId, isUnlocked, cameraConfig)
	return HorseViewportRenderer.GetCatalogSnapshot(catalogId, cameraConfig, {
		Silhouette = not isUnlocked,
	})
end

function HorseIndexViewportCache.GetIfCached()
	return nil
end

function HorseIndexViewportCache.ClearViewport(viewportFrame)
	HorseViewportRenderer.Clear(viewportFrame)
end

function HorseIndexViewportCache.ApplyToViewport(viewportFrame, catalogId, isUnlocked, cameraConfig)
	return HorseViewportRenderer.ApplyCatalog(viewportFrame, catalogId, cameraConfig, {
		Silhouette = not isUnlocked,
	})
end

function HorseIndexViewportCache.Forget()
	-- The shared cache intentionally lives for the whole client session.
end

return HorseIndexViewportCache
