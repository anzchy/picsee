/// Retains only pixels already accepted by a consumer; this port never delivers cached content.
public protocol ImagePresentationPinning: Sendable {
    func pin(_ key: RenderKey, image: DecodedImage) async
    func unpin(_ key: RenderKey) async
}
