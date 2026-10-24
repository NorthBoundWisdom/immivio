extends RefCounted
const MESSAGES := {
	"STRM_EMPTY": "The STRM file is empty.",
	"STRM_TOO_LARGE": "The STRM file exceeds 64 KiB.",
	"STRM_INVALID_TEXT": "The STRM text encoding is invalid.",
	"STRM_MULTIPLE_TARGETS": "A STRM file must contain one media address.",
	"STRM_RECURSIVE": "The STRM references a loop or more than four shortcuts.",
	"STRM_UNSUPPORTED_ADDRESS": "This STRM address type is not supported.",
	"STRM_INVALID_ADDRESS": "The STRM media address is invalid.",
	"STRM_WINDOWS_PATH": "Use an SMB or HTTP address instead of a Windows drive path.",
	"STRM_RELATIVE_PATH_UNAVAILABLE":
	"Use a full media address for a STRM selected through the system picker.",
	"STRM_SMB_CONNECTION_REQUIRED": "Add a matching SMB connection before opening this STRM.",
	"STRM_READ_TIMEOUT": "Reading the STRM timed out.",
	"STRM_ACCESS_DENIED": "Access to the STRM was denied.",
	"STRM_NOT_FOUND": "The STRM file no longer exists.",
	"STRM_READ_FAILED": "The STRM could not be read.",
	"MPV_LOCAL_SOURCE_FAILED": "Unable to open the source. Check access and the connection.",
	"MPV_SOURCE_START_FAILED": "Unable to start playback. Check the media format.",
	"MPV_FRAME_FAILED": "Playback stopped because a video frame could not be displayed."
}


static func summary(code: String) -> String:
	return str(MESSAGES.get(code, code))
