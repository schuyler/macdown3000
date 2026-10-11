# Keep the shared application/Quick Look parser fix reproducible after pod install.
module MacDownHoedownPatches
  ORIGINAL = <<~C.freeze
    \t\tif (pre)
    \t\t\tbeg += pre; /* skipping prefix */

    \t\t/* empty line followed by non-quote line */
  C

  CORRECTED = <<~C.freeze
    \t\tif (pre)
    \t\t\tbeg += pre; /* skipping prefix */

    \t\t/* A heading is a new block, not a lazy paragraph continuation.
    \t\t * Leave the whole line for the enclosing block parser. */
    \t\telse if (is_atxheader(doc, data + beg, end - beg)) {
    \t\t\tend = beg;
    \t\t\tbreak;
    \t\t}

    \t\t/* empty line followed by non-quote line */
  C

  def self.apply(document_path)
    source = File.binread(document_path)
    return if source.include?(CORRECTED)

    unless source.scan(ORIGINAL).length == 1
      raise "Hoedown blockquote parser changed; review the heading boundary patch before building"
    end

    mode = File.stat(document_path).mode & 0o777
    begin
      File.chmod(mode | 0o200, document_path)
      File.binwrite(document_path, source.sub(ORIGINAL, CORRECTED))
    ensure
      File.chmod(mode, document_path)
    end
  end
end
