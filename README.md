# bconv

Bible format converter. Supports amalgamation, morphemes, and various alignment strategies.

Supported formats:
- [STEPBible-Data](https://github.com/STEPBible/STEPBible-Data) .txt files
- CSV
- USFM (`\zaln-s` with `x-lemma` or `x-strong` tags supported)
- OSIS

## XML Schema

For example, Genesis 30:11.
```xml
<w id="gen30:11#1">
  <m type="prefix" code="Hc">וַ</m>
  <m type="root" code="Vqw3fs" lemma="אָמַר">תֹּ֥אמֶר</m>
</w>
<w id="gen30:11#2">
  <m type="root" code="HNpf" lemma="לֵאָ֖ה">לֵאָ֖ה</m>
</w>
<q by="לֵאָ֖ה">
  <variant>
    <option value="qere">
      <w id="gen30:11#3">
        <m type="root" code="HVqp3ms" lemma="בּוֹא">בָּ֣א</m>
      </w>
      <w id="gen30:11#4">
        <m type="root" code="Ncmsa" lemma="גָּד">גָ֑ד</m>
      </w>
    </option>
    <option value="ketiv">
      <w id="gen30:11#5">
        <m type="prefix">בָּ֣</m>
        <m type="root">גָ֑ד</m>
      </w>
    </option>
  </variant>
</q>
<w id="gen30:11#6">
  <m type="prefix" code="Hc">וַ</m>
  <m type="root" code="Vqw3fs">תִּקְרָ֥א</m>
</w>
<w id="gen30:11#7">
  <m type="root" code="Hto" lemma="אֶת">אֵת</m>
</w>
<p>־</p>
<w id="gen30:11#8">
  <m type="root" code="HNcmsc" lemma="שְׁמ֖">שְׁמ֖</m>
  <m type="root" code="Sp3ms">וֹ</m>
</w>
<w id="gen30:11#9">
  <m type="root" code="HNpm" lemma="גָּד">גָּֽד</m>
</w>
<p>׃</p>
```

- `q` = quote
- `w` = word
  - `id` tags need only be unique for derivative works to link back to. Currently the NRSV is used.
- `m` = morpheme
  - currently follows [OpenScriptures](https://hb.openscriptures.org/parsing/HebrewMorphologyCodes.html)
- `p` = punctutation

### Alignment

Translated languages may link back to original languages by id:
```xml
<v n="11">
  <w id="gen30:11#1">Then</w>
  <w id="gen30:11#2">Leah</w>
  <w id="gen30:11#1">said</w>,
  <q by="Leah">
    <w id="gen30:11#5">With good fortune!</w>
  </q>
  <w id="gen30:11#6">So she named</w>
  <w id="gen30:11#8">him</w>
  <w id="gen30:11#9">Gad</w>.
</v>
```

This way they need not be regenerated when the underlying source text is amended.
