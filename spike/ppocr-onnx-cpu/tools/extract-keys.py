"""Derive the PP-OCRv5 character dictionary and cross-check it.

The recogniser ONNX carries the dictionary in its own metadata, which is a
better source than the shipped Paddle payload's inference.yml: it binds the
dictionary to the exact weights being shipped, and it survives the removal of
paddleocr/ in the cleanup issue.

    python extract-keys.py <rec.onnx> <keys.txt> [inference.yml]

With the optional third argument the extracted list is compared against
PostProcess.character_dict from the Paddle payload. The spike found them
byte-identical (18383 entries).

Requires: pip install onnx  (and pyyaml only for the optional cross-check).
"""

import io
import sys

import onnx


def main(argv):
    if not 3 <= len(argv) <= 4:
        print(__doc__)
        return 2

    rec_path, keys_path = argv[1], argv[2]

    model = onnx.load(rec_path, load_external_data=False)
    meta = {kv.key: kv.value for kv in model.metadata_props}
    if "character" not in meta:
        print("FAIL: %s carries no 'character' metadata" % rec_path)
        return 1
    chars = meta["character"].split("\n")

    # index 0 is the CTC blank and the last index is a space; neither belongs in
    # keys.txt. RapidOcrOnnx adds both itself, so a leading blank line here
    # would shift every index by one and decode to garbage.
    classes = model.graph.output[0].type.tensor_type.shape.dim[2].dim_value
    print("dictionary entries: %d" % len(chars))
    print("recogniser classes: %d (= entries + blank + space)" % classes)
    if classes != len(chars) + 2:
        print("FAIL: expected %d classes, model says %d" % (len(chars) + 2, classes))
        return 1

    if len(argv) == 4:
        import yaml

        with io.open(argv[3], encoding="utf-8") as fh:
            cfg = yaml.safe_load(fh)
        yml_chars = cfg["PostProcess"]["character_dict"]
        if yml_chars != chars:
            print("FAIL: ONNX metadata and %s disagree" % argv[3])
            return 1
        print("cross-check against %s: identical" % argv[3])

    # LF, always. RapidOcrOnnx reads with getline and would otherwise keep the
    # CR on every entry.
    with io.open(keys_path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(chars) + "\n")
    print("wrote %s" % keys_path)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
