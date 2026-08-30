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
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"
  license "MIT"
  head "https://github.com/simo-ship-it/Aurora.git", branch: "main"

  depends_on macos: :ventura

  def install
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
