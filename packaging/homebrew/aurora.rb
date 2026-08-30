# Formula, non cask, e di proposito.
#
# Un cask scaricherebbe l'archivio del rilascio, e macOS lo metterebbe in
# quarantena: senza una firma Developer ID — che esiste solo dentro il
# programma Apple a pagamento — l'app verrebbe bloccata al primo avvio con un
# messaggio che parla di file danneggiato. Compilando sulla macchina di chi
# installa, la quarantena non entra proprio in gioco.
class Aurora < Formula
  desc "Markdown editor that renders as you type"
  homepage "https://github.com/simo-ship-it/Aurora"
  url "https://github.com/simo-ship-it/Aurora/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "8a3943e70d904ecbf6965acc1798448857051658f09d4df746a46ff6655bf9cd"
  license "MIT"
  head "https://github.com/simo-ship-it/Aurora.git", branch: "main"

  depends_on macos: :ventura

  def install
    # Homebrew compila già dentro un sandbox, e SwiftPM ne aprirebbe un secondo
    # per valutare Package.swift: annidarli non è permesso, e la compilazione si
    # ferma su "sandbox_apply: Operation not permitted".
    ENV["AURORA_NO_SWIFTPM_SANDBOX"] = "1"
    system "./Scripts/build_app.sh", "release"
    prefix.install "Aurora.app"
    # Perché `aurora documento.md` funzioni dal terminale.
    bin.install_symlink prefix/"Aurora.app/Contents/MacOS/Aurora" => "aurora"
  end

  def caveats
    <<~EOS
      Aurora.app è stata installata in:
        #{prefix}

      Per averla fra le applicazioni:
        ln -sfn #{prefix}/Aurora.app /Applications/Aurora.app

      Compilata sulla tua macchina: nessuna quarantena da sbloccare.
    EOS
  end

  test do
    assert_predicate prefix/"Aurora.app/Contents/MacOS/Aurora", :executable?
    assert_match "io.github.simo-ship-it.Aurora",
                 (prefix/"Aurora.app/Contents/Info.plist").read
  end
end
