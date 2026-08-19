enum MessageType {
  advertisement,
  keyDistribution,
  private,
  file,
  unknown;

  static MessageType fromString(String name) {
    switch (name.toLowerCase()) {
      case 'advert':
        return MessageType.advertisement;
      case 'key_dist':
        return MessageType.keyDistribution;
      case 'private':
        return MessageType.private;
      case 'file':
        return MessageType.file;
      default:
        return MessageType.unknown;
    }
  }
}
