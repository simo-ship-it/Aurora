#!/usr/bin/env python3
"""Genera Resources/<lingua>.lproj/{Localizable,InfoPlist}.strings.

Le traduzioni stanno qui, in una tabella sola, invece che sparse in otto file:
aggiungere una voce significa aggiungere una riga per lingua, e una lingua che
la dimentica si vede a colpo d'occhio (lo script si ferma e la elenca).
La chiave e' la frase inglese, che e' anche il testo mostrato quando manca.
"""
import pathlib
import sys

LANGUAGES = ["en", "it", "es", "fr", "de", "pt-BR", "ja", "zh-Hans"]

# chiave inglese -> {lingua: traduzione}. L'inglese si omette: e' la chiave.
T = {
 "About Aurora": {"it":"Informazioni su Aurora","es":"Acerca de Aurora","fr":"À propos d’Aurora","de":"Über Aurora","pt-BR":"Sobre o Aurora","ja":"Auroraについて","zh-Hans":"关于 Aurora"},
 "Settings…": {"it":"Impostazioni…","es":"Ajustes…","fr":"Réglages…","de":"Einstellungen…","pt-BR":"Ajustes…","ja":"設定…","zh-Hans":"设置…"},
 "Hide Aurora": {"it":"Nascondi Aurora","es":"Ocultar Aurora","fr":"Masquer Aurora","de":"Aurora ausblenden","pt-BR":"Ocultar Aurora","ja":"Auroraを隠す","zh-Hans":"隐藏 Aurora"},
 "Hide Others": {"it":"Nascondi altre","es":"Ocultar otros","fr":"Masquer les autres","de":"Andere ausblenden","pt-BR":"Ocultar Outros","ja":"ほかを隠す","zh-Hans":"隐藏其他"},
 "Show All": {"it":"Mostra tutte","es":"Mostrar todo","fr":"Tout afficher","de":"Alle einblenden","pt-BR":"Mostrar Tudo","ja":"すべてを表示","zh-Hans":"全部显示"},
 "Quit Aurora": {"it":"Esci da Aurora","es":"Salir de Aurora","fr":"Quitter Aurora","de":"Aurora beenden","pt-BR":"Encerrar Aurora","ja":"Auroraを終了","zh-Hans":"退出 Aurora"},

 "File": {"it":"File","es":"Archivo","fr":"Fichier","de":"Ablage","pt-BR":"Arquivo","ja":"ファイル","zh-Hans":"文件"},
 "New": {"it":"Nuovo","es":"Nuevo","fr":"Nouveau","de":"Neu","pt-BR":"Novo","ja":"新規","zh-Hans":"新建"},
 "Open": {"it":"Apri","es":"Abrir","fr":"Ouvrir","de":"Öffnen","pt-BR":"Abrir","ja":"開く","zh-Hans":"打开"},
 "Open…": {"it":"Apri…","es":"Abrir…","fr":"Ouvrir…","de":"Öffnen…","pt-BR":"Abrir…","ja":"開く…","zh-Hans":"打开…"},
 "Open Folder…": {"it":"Apri cartella…","es":"Abrir carpeta…","fr":"Ouvrir un dossier…","de":"Ordner öffnen…","pt-BR":"Abrir Pasta…","ja":"フォルダを開く…","zh-Hans":"打开文件夹…"},
 "Open Recent": {"it":"Apri recenti","es":"Abrir recientes","fr":"Ouvrir l’élément récent","de":"Benutzte Dokumente","pt-BR":"Abrir Recente","ja":"最近使った項目を開く","zh-Hans":"打开最近使用"},
 "Clear Menu": {"it":"Svuota menu","es":"Vaciar menú","fr":"Vider le menu","de":"Menü löschen","pt-BR":"Limpar Menu","ja":"メニューをクリア","zh-Hans":"清除菜单"},
 "Close": {"it":"Chiudi","es":"Cerrar","fr":"Fermer","de":"Schließen","pt-BR":"Fechar","ja":"閉じる","zh-Hans":"关闭"},
 "Save": {"it":"Salva","es":"Guardar","fr":"Enregistrer","de":"Sichern","pt-BR":"Salvar","ja":"保存","zh-Hans":"存储"},
 "Save As…": {"it":"Salva con nome…","es":"Guardar como…","fr":"Enregistrer sous…","de":"Sichern unter…","pt-BR":"Salvar Como…","ja":"別名で保存…","zh-Hans":"存储为…"},
 "Revert to Saved": {"it":"Ripristina versione salvata","es":"Volver a la versión guardada","fr":"Revenir à la version enregistrée","de":"Zur gesicherten Version zurückkehren","pt-BR":"Reverter para o Salvo","ja":"保存されたバージョンに戻す","zh-Hans":"复原到已存储版本"},
 "Print…": {"it":"Stampa…","es":"Imprimir…","fr":"Imprimer…","de":"Drucken…","pt-BR":"Imprimir…","ja":"プリント…","zh-Hans":"打印…"},

 "Edit": {"it":"Modifica","es":"Edición","fr":"Édition","de":"Bearbeiten","pt-BR":"Editar","ja":"編集","zh-Hans":"编辑"},
 "Undo": {"it":"Annulla","es":"Deshacer","fr":"Annuler","de":"Widerrufen","pt-BR":"Desfazer","ja":"取り消す","zh-Hans":"撤销"},
 "Redo": {"it":"Ripristina","es":"Rehacer","fr":"Rétablir","de":"Wiederholen","pt-BR":"Refazer","ja":"やり直す","zh-Hans":"重做"},
 "Cut": {"it":"Taglia","es":"Cortar","fr":"Couper","de":"Ausschneiden","pt-BR":"Cortar","ja":"カット","zh-Hans":"剪切"},
 "Copy": {"it":"Copia","es":"Copiar","fr":"Copier","de":"Kopieren","pt-BR":"Copiar","ja":"コピー","zh-Hans":"拷贝"},
 "Paste": {"it":"Incolla","es":"Pegar","fr":"Coller","de":"Einsetzen","pt-BR":"Colar","ja":"ペースト","zh-Hans":"粘贴"},
 "Select All": {"it":"Seleziona tutto","es":"Seleccionar todo","fr":"Tout sélectionner","de":"Alles auswählen","pt-BR":"Selecionar Tudo","ja":"すべてを選択","zh-Hans":"全选"},
 "Find": {"it":"Cerca","es":"Buscar","fr":"Rechercher","de":"Suchen","pt-BR":"Buscar","ja":"検索","zh-Hans":"查找"},
 "Find…": {"it":"Cerca…","es":"Buscar…","fr":"Rechercher…","de":"Suchen…","pt-BR":"Buscar…","ja":"検索…","zh-Hans":"查找…"},
 "Find Next": {"it":"Successivo","es":"Buscar siguiente","fr":"Rechercher le suivant","de":"Weitersuchen","pt-BR":"Buscar Próxima","ja":"次を検索","zh-Hans":"查找下一个"},
 "Find Previous": {"it":"Precedente","es":"Buscar anterior","fr":"Rechercher le précédent","de":"Rückwärts suchen","pt-BR":"Buscar Anterior","ja":"前を検索","zh-Hans":"查找上一个"},
 "Use Selection for Find": {"it":"Usa selezione per cercare","es":"Usar selección para buscar","fr":"Rechercher la sélection","de":"Auswahl suchen","pt-BR":"Usar Seleção para Busca","ja":"選択部分を検索に使用","zh-Hans":"用所选内容查找"},
 "Check Spelling While Typing": {"it":"Controllo ortografia durante la scrittura","es":"Comprobar ortografía mientras se escribe","fr":"Vérifier l’orthographe lors de la saisie","de":"Rechtschreibung während der Eingabe prüfen","pt-BR":"Verificar Ortografia ao Digitar","ja":"入力中にスペルチェック","zh-Hans":"键入时检查拼写"},

 "Format": {"it":"Formato","es":"Formato","fr":"Format","de":"Format","pt-BR":"Formatar","ja":"フォーマット","zh-Hans":"格式"},
 "Bold": {"it":"Grassetto","es":"Negrita","fr":"Gras","de":"Fett","pt-BR":"Negrito","ja":"太字","zh-Hans":"粗体"},
 "Italic": {"it":"Corsivo","es":"Cursiva","fr":"Italique","de":"Kursiv","pt-BR":"Itálico","ja":"斜体","zh-Hans":"斜体"},
 "Strikethrough": {"it":"Barrato","es":"Tachado","fr":"Barré","de":"Durchgestrichen","pt-BR":"Tachado","ja":"取り消し線","zh-Hans":"删除线"},
 "Highlight": {"it":"Evidenziato","es":"Resaltado","fr":"Surlignage","de":"Hervorgehoben","pt-BR":"Destaque","ja":"ハイライト","zh-Hans":"高亮"},
 "Inline Code": {"it":"Codice inline","es":"Código en línea","fr":"Code en ligne","de":"Inline-Code","pt-BR":"Código em Linha","ja":"インラインコード","zh-Hans":"行内代码"},
 "Paragraph": {"it":"Paragrafo","es":"Párrafo","fr":"Paragraphe","de":"Absatz","pt-BR":"Parágrafo","ja":"段落","zh-Hans":"段落"},
 "Heading %d": {"it":"Titolo %d","es":"Título %d","fr":"Titre %d","de":"Überschrift %d","pt-BR":"Título %d","ja":"見出し %d","zh-Hans":"标题 %d"},
 "Bulleted List": {"it":"Elenco puntato","es":"Lista con viñetas","fr":"Liste à puces","de":"Aufzählung","pt-BR":"Lista com Marcadores","ja":"箇条書きリスト","zh-Hans":"项目符号列表"},
 "Task List": {"it":"Elenco di attività","es":"Lista de tareas","fr":"Liste de tâches","de":"Aufgabenliste","pt-BR":"Lista de Tarefas","ja":"タスクリスト","zh-Hans":"任务列表"},
 "Blockquote": {"it":"Citazione","es":"Cita","fr":"Citation","de":"Zitat","pt-BR":"Citação","ja":"引用","zh-Hans":"引用"},
 "Code Block": {"it":"Blocco di codice","es":"Bloque de código","fr":"Bloc de code","de":"Codeblock","pt-BR":"Bloco de Código","ja":"コードブロック","zh-Hans":"代码块"},
 "Link": {"it":"Collegamento","es":"Enlace","fr":"Lien","de":"Link","pt-BR":"Link","ja":"リンク","zh-Hans":"链接"},
 "Link…": {"it":"Collegamento…","es":"Enlace…","fr":"Lien…","de":"Link…","pt-BR":"Link…","ja":"リンク…","zh-Hans":"链接…"},
 "Horizontal Rule": {"it":"Linea orizzontale","es":"Línea horizontal","fr":"Ligne horizontale","de":"Horizontale Linie","pt-BR":"Linha Horizontal","ja":"水平線","zh-Hans":"水平线"},

 "View": {"it":"Vista","es":"Visualización","fr":"Présentation","de":"Darstellung","pt-BR":"Visualizar","ja":"表示","zh-Hans":"显示"},
 "Toggle Full Screen": {"it":"Attiva/disattiva schermo intero","es":"Activar/desactivar pantalla completa","fr":"Activer/désactiver le plein écran","de":"Vollbild ein/aus","pt-BR":"Ativar/Desativar Tela Cheia","ja":"フルスクリーンの切り替え","zh-Hans":"切换全屏幕"},
 "Window": {"it":"Finestra","es":"Ventana","fr":"Fenêtre","de":"Fenster","pt-BR":"Janela","ja":"ウインドウ","zh-Hans":"窗口"},
 "Minimize": {"it":"Riduci a icona","es":"Minimizar","fr":"Réduire","de":"Im Dock ablegen","pt-BR":"Minimizar","ja":"しまう","zh-Hans":"最小化"},
 "Zoom": {"it":"Zoom","es":"Zoom","fr":"Zoom","de":"Zoomen","pt-BR":"Zoom","ja":"拡大/縮小","zh-Hans":"缩放"},
 "Bring All to Front": {"it":"Porta tutto in primo piano","es":"Traer todo al frente","fr":"Tout ramener au premier plan","de":"Alle nach vorne bringen","pt-BR":"Trazer Tudo para a Frente","ja":"すべてを手前に移動","zh-Hans":"前置全部窗口"},

 "Choose the folder to work in.": {"it":"Scegli la cartella su cui lavorare.","es":"Elige la carpeta en la que trabajar.","fr":"Choisissez le dossier de travail.","de":"Wähle den Ordner, in dem du arbeiten möchtest.","pt-BR":"Escolha a pasta na qual trabalhar.","ja":"作業するフォルダを選択してください。","zh-Hans":"请选择要使用的文件夹。"},
 "Working folder": {"it":"Cartella di lavoro","es":"Carpeta de trabajo","fr":"Dossier de travail","de":"Arbeitsordner","pt-BR":"Pasta de trabalho","ja":"作業フォルダ","zh-Hans":"工作文件夹"},
 "Files in the working folder": {"it":"File della cartella di lavoro","es":"Archivos de la carpeta de trabajo","fr":"Fichiers du dossier de travail","de":"Dateien im Arbeitsordner","pt-BR":"Arquivos da pasta de trabalho","ja":"作業フォルダ内のファイル","zh-Hans":"工作文件夹中的文件"},
 "Choose the working folder": {"it":"Scegli la cartella di lavoro","es":"Elegir la carpeta de trabajo","fr":"Choisir le dossier de travail","de":"Arbeitsordner wählen","pt-BR":"Escolher a pasta de trabalho","ja":"作業フォルダを選択","zh-Hans":"选择工作文件夹"},
 "No Folder": {"it":"Nessuna cartella","es":"Sin carpeta","fr":"Aucun dossier","de":"Kein Ordner","pt-BR":"Nenhuma pasta","ja":"フォルダなし","zh-Hans":"无文件夹"},
 "Click the name above to choose a folder.": {"it":"Premi il nome qui sopra per scegliere una cartella.","es":"Haz clic en el nombre de arriba para elegir una carpeta.","fr":"Cliquez sur le nom ci-dessus pour choisir un dossier.","de":"Klicke oben auf den Namen, um einen Ordner zu wählen.","pt-BR":"Clique no nome acima para escolher uma pasta.","ja":"上の名前をクリックしてフォルダを選択します。","zh-Hans":"点按上方的名称以选择文件夹。"},
 "This folder contains no Markdown documents.": {"it":"Questa cartella non contiene documenti Markdown.","es":"Esta carpeta no contiene documentos Markdown.","fr":"Ce dossier ne contient aucun document Markdown.","de":"Dieser Ordner enthält keine Markdown-Dokumente.","pt-BR":"Esta pasta não contém documentos Markdown.","ja":"このフォルダにMarkdown書類はありません。","zh-Hans":"此文件夹中没有 Markdown 文稿。"},

 "text": {"it":"testo","es":"texto","fr":"texte","de":"Text","pt-BR":"texto","ja":"テキスト","zh-Hans":"文本"},
 "plain text": {"it":"testo normale","es":"texto normal","fr":"texte normal","de":"einfacher Text","pt-BR":"texto simples","ja":"標準テキスト","zh-Hans":"纯文本"},
 "[text](url)": {"it":"[testo](url)","es":"[texto](url)","fr":"[texte](url)","de":"[Text](URL)","pt-BR":"[texto](url)","ja":"[テキスト](url)","zh-Hans":"[文本](url)"},

 "Settings": {"it":"Impostazioni","es":"Ajustes","fr":"Réglages","de":"Einstellungen","pt-BR":"Ajustes","ja":"設定","zh-Hans":"设置"},
 "System Font": {"it":"Font di sistema","es":"Tipo de letra del sistema","fr":"Police système","de":"Systemschrift","pt-BR":"Fonte do sistema","ja":"システムフォント","zh-Hans":"系统字体"},
 "Restore Defaults": {"it":"Ripristina valori predefiniti","es":"Restablecer valores por omisión","fr":"Rétablir les valeurs par défaut","de":"Standardwerte wiederherstellen","pt-BR":"Restaurar Padrões","ja":"デフォルトに戻す","zh-Hans":"恢复默认值"},
 "Font:": {"it":"Font:","es":"Tipo de letra:","fr":"Police :","de":"Schrift:","pt-BR":"Fonte:","ja":"フォント:","zh-Hans":"字体："},
 "Text size:": {"it":"Dimensione testo:","es":"Tamaño del texto:","fr":"Taille du texte :","de":"Textgröße:","pt-BR":"Tamanho do texto:","ja":"文字サイズ:","zh-Hans":"文字大小："},
 "Line spacing:": {"it":"Interlinea:","es":"Interlineado:","fr":"Interligne :","de":"Zeilenabstand:","pt-BR":"Entrelinhas:","ja":"行間:","zh-Hans":"行距："},
 "Column width:": {"it":"Larghezza colonna:","es":"Ancho de columna:","fr":"Largeur de colonne :","de":"Spaltenbreite:","pt-BR":"Largura da coluna:","ja":"段の幅:","zh-Hans":"栏宽："},
 "Appearance:": {"it":"Aspetto:","es":"Aspecto:","fr":"Apparence :","de":"Erscheinungsbild:","pt-BR":"Aparência:","ja":"外観:","zh-Hans":"外观："},
 "Match System": {"it":"Come il sistema","es":"Según el sistema","fr":"Selon le système","de":"Wie System","pt-BR":"Igual ao sistema","ja":"システムに合わせる","zh-Hans":"跟随系统"},
 "Light": {"it":"Chiaro","es":"Claro","fr":"Clair","de":"Hell","pt-BR":"Clara","ja":"ライト","zh-Hans":"浅色"},
 "Dark": {"it":"Scuro","es":"Oscuro","fr":"Sombre","de":"Dunkel","pt-BR":"Escura","ja":"ダーク","zh-Hans":"深色"},
}

# Il menu dei comandi "/" nomina i titoli uno per uno, mentre il menu Formato
# li numera: le sei voci si ricavano dallo stesso modello, senza ripeterlo.
for level in range(1, 7):
    T["Heading %d" % level] = {
        lang: T["Heading %d"][lang].replace("%d", str(level)) for lang in T["Heading %d"]
    }

# Nomi dei tipi di documento: li legge Launch Services, non il codice.
INFO = {
 "Markdown Document": {"it":"Documento Markdown","es":"Documento Markdown","fr":"Document Markdown","de":"Markdown-Dokument","pt-BR":"Documento Markdown","ja":"Markdown書類","zh-Hans":"Markdown 文稿"},
 "Plain Text Document": {"it":"Documento di testo","es":"Documento de texto","fr":"Document texte","de":"Textdokument","pt-BR":"Documento de texto","ja":"テキスト書類","zh-Hans":"纯文本文稿"},
}


def escape(value):
    return value.replace("\\", "\\\\").replace('"', '\\"')


def render(table, lang):
    lines = ['/* Aurora — %s. Generato da Scripts/make_strings.py: non modificare a mano. */' % lang, ""]
    for key in table:
        value = key if lang == "en" else table[key][lang]
        lines.append('"%s" = "%s";' % (escape(key), escape(value)))
    return "\n".join(lines) + "\n"


def main():
    missing = [
        "%s (%s)" % (key, lang)
        for table in (T, INFO) for key in table
        for lang in LANGUAGES if lang != "en" and lang not in table[key]
    ]
    if missing:
        print("Traduzioni mancanti:\n  " + "\n  ".join(missing), file=sys.stderr)
        return 1

    root = pathlib.Path(__file__).resolve().parent.parent / "Resources"
    for lang in LANGUAGES:
        folder = root / ("%s.lproj" % lang)
        folder.mkdir(parents=True, exist_ok=True)
        (folder / "Localizable.strings").write_text(render(T, lang), encoding="utf-8")
        (folder / "InfoPlist.strings").write_text(render(INFO, lang), encoding="utf-8")
    print("Scritte %d lingue × %d voci in %s" % (len(LANGUAGES), len(T), root))
    return 0


if __name__ == "__main__":
    sys.exit(main())
