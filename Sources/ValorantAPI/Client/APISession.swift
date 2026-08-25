import Foundation
import HandyOperators

public struct APISession: Codable, Equatable {
	public var accessToken: AccessToken
	public var entitlementsToken: String
	public var cookies: [Cookie]
}

public struct Cookie: Codable, Hashable {
	public var name: String
	public var value: String
	public var domain: String
	public var path: String
	
	public init(name: String, value: String, domain: String, path: String) {
		self.name = name
		self.value = value
		self.domain = domain
		self.path = path
	}
	
	init(_ httpCookie: HTTPCookie) {
		name = httpCookie.name
		value = httpCookie.value
		domain = httpCookie.domain
		path = httpCookie.path
	}
	
	var httpCookie: HTTPCookie {
		.init(properties: [
			.name: name,
			.value: value,
			.domain: domain,
			.path: path,
		])!
	}
}

public struct AccessToken: Codable, Hashable {
	public var type: String
	public var token: String
	public var expiration: Date
	
	public init(type: String, token: String, expiration: Date) {
		self.type = type
		self.token = token
		self.expiration = expiration
	}
	
	var encoded: String {
		"\(type) \(token)"
	}
	
	var hasExpired: Bool {
		expiration < .now
	}
}

extension APISession {
	public init(
		username: String, password: String,
		urlSessionOverride: URLSession? = nil,
		multifactorHandler: MultifactorHandler
	) async throws {
		let client = await AuthClient(urlSessionOverride: urlSessionOverride)
		try await client.establishSession()
		
		self.accessToken = try await client.getAccessToken(
			username: username, password: password,
			multifactorHandler: multifactorHandler
		)
		await client.setAccessToken(accessToken)
		
		self.entitlementsToken = try await client
			.getEntitlementsToken()
		
		self.cookies = await client.cookies().map(Cookie.init)
	}
	
	mutating func refreshAccessToken() async throws {
		let client = await AuthClient()
		await client.setCookies(cookies.map(\.httpCookie))
		self.accessToken = try await client.refreshAccessToken()
		??? RefreshError.sessionExpired
	}
	
	enum EstablishmentError: Error {
		case noSessionIDCookie
		case noTDIDCookie
	}
	
	enum RefreshError: Error {
		case sessionExpired
	}
}

extension AccessToken {
	func extractUserID() throws -> User.ID {
		let tokenParts = try token.split(separator: ".")
		??? ExtractionError.tokenMissing
		
		let tokenInfoIndex = 1
		guard tokenParts.indices.contains(tokenInfoIndex) else {
			throw ExtractionError.notEnoughParts(tokenParts.count)
		}
		
		// this initializer requires padding (to a multiple of 4), which JWTs don't typically have
		let unpadded = tokenParts[tokenInfoIndex]
		let base64String = unpadded.padding(
			toLength: (unpadded.count + 3) / 4 * 4,
			withPad: "=",
			startingAt: 0
		)
		let rawTokenInfo = try Data(base64Encoded: base64String)
		??? ExtractionError.base64DecodingFailed(base64String)
		
		do {
			return try ValorantClient.responseDecoder.decode(AccessTokenInfo.self, from: rawTokenInfo).sub
		} catch let error as DecodingError {
			throw ExtractionError.decodingError(error)
		}
	}
	
	private struct AccessTokenInfo: Decodable {
		let sub: User.ID
		// don't care about the rest
	}
	
	private enum ExtractionError: Error, LocalizedError {
		case tokenMissing
		case notEnoughParts(Int)
		case base64DecodingFailed(String)
		case decodingError(DecodingError)
		
		var failureReason: String? {
			switch self {
			case .tokenMissing:
				return "No token found."
			case .notEnoughParts(let partCount):
				return "Not enough JWT parts—found \(partCount)."
			case .base64DecodingFailed(let base64String):
				return "Could not decode Base64 string '\(base64String)'."
			case .decodingError(let error):
				return "Decoding failed:\n\("" <- { dump(error, to: &$0) })"
			}
		}
	}
}
