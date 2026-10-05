import Darwin
import Foundation
import GalpiumCore

do {
  let args = CommandLine.arguments
  if args.count == 7, args[1] == "--supervise", let owner = Int32(args[2]), owner > 0,
    args[3] == "--port", let port = UInt16(args[4]), port > 0, args[5] == "--key-file",
    args[6].hasPrefix("/")
  {
    try EmbeddingWorker.supervise(owner: owner, port: args[4], keyFile: args[6])
  } else if args.count == 3, args[1] == "--library", args[2].hasPrefix("/") {
    try EmbeddingWorker.run(root: URL(fileURLWithPath: args[2], isDirectory: true))
  } else {
    throw WikiError.invalid("embedder arguments")
  }
} catch {
  FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
  exit(1)
}
