import Foundation
import Protoquest

extension ValorantClient {
	/// Fetches the current client version directly from Riot's session endpoint.
	/// This is the authoritative, always-up-to-date source—unlike the third-party
	/// valorant-api.com version endpoint, which can lag behind a fresh Riot patch
	/// (leading to 409 "client version mismatch" errors).
	public func getSessionClientVersion() async throws -> String {
		try await send(SessionRequest(playerID: userID, location: location)).version
	}
}

private struct SessionRequest: GetJSONRequest, LiveGameRequest {
	var playerID: Player.ID
	var location: Location

	var path: String {
		"/session/v1/sessions/\(playerID)"
	}

	struct Response: Decodable {
		var version: String

		private enum CodingKeys: String, CodingKey {
			case pascal = "Version"
			case camel = "version"
		}

		init(from decoder: Decoder) throws {
			let container = try decoder.container(keyedBy: CodingKeys.self)
			if let pascal = try container.decodeIfPresent(String.self, forKey: .pascal) {
				version = pascal
			} else if let camel = try container.decodeIfPresent(String.self, forKey: .camel) {
				version = camel
			} else {
				throw DecodingError.keyNotFound(
					CodingKeys.camel,
					DecodingError.Context(
						codingPath: decoder.codingPath,
						debugDescription: "Session response is missing a version field."
					)
				)
			}
		}
	}
}
