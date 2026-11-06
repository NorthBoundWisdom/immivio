extends RefCounted
## Provider key normalization adapted from Thru3D; marks use Immivio's own line glyphs.
const MARKS := {
	"emby": "provider_emby",
	"jellyfin": "provider_jellyfin",
	"plex": "provider_plex",
	"xbvr": "provider_xbvr",
	"dlna": "cast",
	"smb": "server",
	"local": "device",
	"file": "device",
	"content": "device"
}


static func key(provider: String, fallback: String = "server") -> String:
	return str(MARKS.get(provider.strip_edges().to_lower(), fallback))
