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
 "New Folder": {"it":"Nuova cartella","es":"Nueva carpeta","fr":"Nouveau dossier","de":"Neuer Ordner","pt-BR":"Nova pasta","ja":"新規フォルダ","zh-Hans":"新建文件夹"},
 "Choose a name.": {"it":"Scegli un nome.","es":"Elige un nombre.","fr":"Choisissez un nom.","de":"Wähle einen Namen.","pt-BR":"Escolha um nome.","ja":"名前を選んでください。","zh-Hans":"请选择名称。"},
 "Create": {"it":"Crea","es":"Crear","fr":"Créer","de":"Erstellen","pt-BR":"Criar","ja":"作成","zh-Hans":"创建"},
 "OK": {"it":"OK","es":"Aceptar","fr":"OK","de":"OK","pt-BR":"OK","ja":"OK","zh-Hans":"好"},
 "An item with this name already exists.": {"it":"Esiste già un elemento con questo nome.","es":"Ya existe un elemento con este nombre.","fr":"Un élément portant ce nom existe déjà.","de":"Ein Element mit diesem Namen ist bereits vorhanden.","pt-BR":"Já existe um item com este nome.","ja":"同じ名前の項目がすでに存在します。","zh-Hans":"已存在同名项目。"},
 "A folder cannot be moved into itself.": {"it":"Una cartella non può essere spostata dentro sé stessa.","es":"Una carpeta no se puede mover dentro de sí misma.","fr":"Un dossier ne peut pas être déplacé dans lui-même.","de":"Ein Ordner kann nicht in sich selbst verschoben werden.","pt-BR":"Uma pasta não pode ser movida para dentro de si mesma.","ja":"フォルダを自分自身の中へ移動することはできません。","zh-Hans":"文件夹不能移动到自身内部。"},
 "Rename…": {"it":"Rinomina…","es":"Renombrar…","fr":"Renommer…","de":"Umbenennen…","pt-BR":"Renomear…","ja":"名前を変更…","zh-Hans":"重新命名…"},
 "Duplicate": {"it":"Duplica","es":"Duplicar","fr":"Dupliquer","de":"Duplizieren","pt-BR":"Duplicar","ja":"複製","zh-Hans":"制作副本"},
 "Move To…": {"it":"Sposta in…","es":"Mover a…","fr":"Déplacer vers…","de":"Bewegen nach…","pt-BR":"Mover para…","ja":"移動先…","zh-Hans":"移动到…"},
 "Choose the destination folder.": {"it":"Scegli la cartella di destinazione.","es":"Elige la carpeta de destino.","fr":"Choisissez le dossier de destination.","de":"Wähle den Zielordner.","pt-BR":"Escolha a pasta de destino.","ja":"移動先のフォルダを選んでください。","zh-Hans":"请选择目标文件夹。"},
 "copy": {"it":"copia","es":"copia","fr":"copie","de":"Kopie","pt-BR":"cópia","ja":"コピー","zh-Hans":"副本"},
 "copy %d": {"it":"copia %d","es":"copia %d","fr":"copie %d","de":"Kopie %d","pt-BR":"cópia %d","ja":"コピー %d","zh-Hans":"副本 %d"},
 "Open": {"it":"Apri","es":"Abrir","fr":"Ouvrir","de":"Öffnen","pt-BR":"Abrir","ja":"開く","zh-Hans":"打开"},
 "Open Side by Side…": {"it": "Apri affiancato…", "es": "Abrir en paralelo…", "fr": "Ouvrir côte à côte…", "de": "Nebeneinander öffnen…", "pt-BR": "Abrir lado a lado…", "ja": "並べて開く…", "zh-Hans": "并排打开…"},
 "Open Side by Side": {"it": "Apri affiancato", "es": "Abrir en paralelo", "fr": "Ouvrir côte à côte", "de": "Nebeneinander öffnen", "pt-BR": "Abrir lado a lado", "ja": "並べて開く", "zh-Hans": "并排打开"},
 "Choose a second document to display beside the current one.": {"it": "Scegli un secondo documento da affiancare a quello attuale.", "es": "Elige un segundo documento para mostrar junto al actual.", "fr": "Choisissez un second document à afficher à côté du document actuel.", "de": "Wähle ein zweites Dokument, das neben dem aktuellen angezeigt werden soll.", "pt-BR": "Escolha um segundo documento para exibir ao lado do atual.", "ja": "現在の書類の横に表示する2つ目の書類を選んでください。", "zh-Hans": "选择要在当前文稿旁显示的第二份文稿。"},
 "Focus Other Document": {"it": "Passa all’altro documento", "es": "Ir al otro documento", "fr": "Passer à l’autre document", "de": "Zum anderen Dokument wechseln", "pt-BR": "Ir para o outro documento", "ja": "もう一方の書類に移動", "zh-Hans": "切换到另一份文稿"},
 "Separate Documents": {"it": "Separa documenti", "es": "Separar documentos", "fr": "Séparer les documents", "de": "Dokumente trennen", "pt-BR": "Separar documentos", "ja": "書類を別々のウインドウにする", "zh-Hans": "分离文稿"},
 "Open in Separate Window": {"it": "Apri in una finestra separata", "es": "Abrir en una ventana separada", "fr": "Ouvrir dans une fenêtre séparée", "de": "In separatem Fenster öffnen", "pt-BR": "Abrir em uma janela separada", "ja": "別のウインドウで開く", "zh-Hans": "在独立窗口中打开"},
 "Close Document": {"it": "Chiudi documento", "es": "Cerrar documento", "fr": "Fermer le document", "de": "Dokument schließen", "pt-BR": "Fechar documento", "ja": "書類を閉じる", "zh-Hans": "关闭文稿"},
 "Unsaved Changes": {"it": "Modifiche non salvate", "es": "Cambios sin guardar", "fr": "Modifications non enregistrées", "de": "Ungesicherte Änderungen", "pt-BR": "Alterações não salvas", "ja": "未保存の変更", "zh-Hans": "未保存的更改"},
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
 "Delete": {"it":"Elimina","es":"Eliminar","fr":"Supprimer","de":"Löschen","pt-BR":"Excluir","ja":"削除","zh-Hans":"删除"},
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
 "Underline": {"it":"Sottolineato","es":"Subrayado","fr":"Souligné","de":"Unterstrichen","pt-BR":"Sublinhado","ja":"下線","zh-Hans":"下划线"},
 "Strikethrough": {"it":"Barrato","es":"Tachado","fr":"Barré","de":"Durchgestrichen","pt-BR":"Tachado","ja":"取り消し線","zh-Hans":"删除线"},
 "Highlight": {"it":"Evidenziato","es":"Resaltado","fr":"Surlignage","de":"Hervorgehoben","pt-BR":"Destaque","ja":"ハイライト","zh-Hans":"高亮"},
 "Inline Code": {"it":"Codice inline","es":"Código en línea","fr":"Code en ligne","de":"Inline-Code","pt-BR":"Código em Linha","ja":"インラインコード","zh-Hans":"行内代码"},
 "Paragraph": {"it":"Paragrafo","es":"Párrafo","fr":"Paragraphe","de":"Absatz","pt-BR":"Parágrafo","ja":"段落","zh-Hans":"段落"},
 "Promote Heading": {"it":"Alza livello del titolo","es":"Subir nivel del título","fr":"Promouvoir le titre","de":"Überschrift hochstufen","pt-BR":"Elevar nível do título","ja":"見出しレベルを上げる","zh-Hans":"提升标题级别"},
 "Demote Heading": {"it":"Abbassa livello del titolo","es":"Bajar nivel del título","fr":"Rétrograder le titre","de":"Überschrift herabstufen","pt-BR":"Rebaixar nível do título","ja":"見出しレベルを下げる","zh-Hans":"降低标题级别"},
 "Heading %d": {"it":"Titolo %d","es":"Título %d","fr":"Titre %d","de":"Überschrift %d","pt-BR":"Título %d","ja":"見出し %d","zh-Hans":"标题 %d"},
 "Bulleted List": {"it":"Elenco puntato","es":"Lista con viñetas","fr":"Liste à puces","de":"Aufzählung","pt-BR":"Lista com Marcadores","ja":"箇条書きリスト","zh-Hans":"项目符号列表"},
 "Ordered List": {"it":"Elenco numerato","es":"Lista numerada","fr":"Liste numérotée","de":"Nummerierte Liste","pt-BR":"Lista Numerada","ja":"番号付きリスト","zh-Hans":"编号列表"},
 "Task List": {"it":"Elenco di attività","es":"Lista de tareas","fr":"Liste de tâches","de":"Aufgabenliste","pt-BR":"Lista de Tarefas","ja":"タスクリスト","zh-Hans":"任务列表"},
 "Blockquote": {"it":"Citazione","es":"Cita","fr":"Citation","de":"Zitat","pt-BR":"Citação","ja":"引用","zh-Hans":"引用"},
 "Code Block": {"it":"Blocco di codice","es":"Bloque de código","fr":"Bloc de code","de":"Codeblock","pt-BR":"Bloco de Código","ja":"コードブロック","zh-Hans":"代码块"},
 "Table": {"it":"Tabella","es":"Tabla","fr":"Tableau","de":"Tabelle","pt-BR":"Tabela","ja":"表","zh-Hans":"表格"},
 "Table…": {"it":"Tabella…","es":"Tabla…","fr":"Tableau…","de":"Tabelle…","pt-BR":"Tabela…","ja":"表…","zh-Hans":"表格…"},
 "Edit Table…": {"it":"Modifica tabella…","es":"Editar tabla…","fr":"Modifier le tableau…","de":"Tabelle bearbeiten…","pt-BR":"Editar tabela…","ja":"表を編集…","zh-Hans":"编辑表格…"},
 "Rows:": {"it":"Righe:","es":"Filas:","fr":"Lignes :","de":"Zeilen:","pt-BR":"Linhas:","ja":"行:","zh-Hans":"行："},
 "Columns:": {"it":"Colonne:","es":"Columnas:","fr":"Colonnes :","de":"Spalten:","pt-BR":"Colunas:","ja":"列:","zh-Hans":"列："},
 "Add Row": {"it":"Aggiungi riga","es":"Añadir fila","fr":"Ajouter une ligne","de":"Zeile hinzufügen","pt-BR":"Adicionar linha","ja":"行を追加","zh-Hans":"添加行"},
 "Add Column": {"it":"Aggiungi colonna","es":"Añadir columna","fr":"Ajouter une colonne","de":"Spalte hinzufügen","pt-BR":"Adicionar coluna","ja":"列を追加","zh-Hans":"添加列"},
 "Remove Row": {"it":"Rimuovi riga","es":"Eliminar fila","fr":"Supprimer la ligne","de":"Zeile entfernen","pt-BR":"Remover linha","ja":"行を削除","zh-Hans":"移除行"},
 "Remove Column": {"it":"Rimuovi colonna","es":"Eliminar columna","fr":"Supprimer la colonne","de":"Spalte entfernen","pt-BR":"Remover coluna","ja":"列を削除","zh-Hans":"移除列"},
 "Remove Row %d": {"it":"Rimuovi riga %d","es":"Eliminar fila %d","fr":"Supprimer la ligne %d","de":"Zeile %d entfernen","pt-BR":"Remover linha %d","ja":"%d行を削除","zh-Hans":"移除第 %d 行"},
 "Remove Column %d": {"it":"Rimuovi colonna %d","es":"Eliminar columna %d","fr":"Supprimer la colonne %d","de":"Spalte %d entfernen","pt-BR":"Remover coluna %d","ja":"列%dを削除","zh-Hans":"移除第 %d 列"},
 "Add Row Below %d": {"it":"Aggiungi riga sotto la riga %d","es":"Añadir fila debajo de la fila %d","fr":"Ajouter une ligne sous la ligne %d","de":"Zeile unter Zeile %d hinzufügen","pt-BR":"Adicionar linha abaixo da linha %d","ja":"%d行の下に追加","zh-Hans":"在第 %d 行下方添加"},
 "Add Column After %d": {"it":"Aggiungi colonna dopo la colonna %d","es":"Añadir columna después de la columna %d","fr":"Ajouter une colonne après la colonne %d","de":"Spalte nach Spalte %d hinzufügen","pt-BR":"Adicionar coluna após a coluna %d","ja":"列%dの後に追加","zh-Hans":"在第 %d 列后添加"},
 "Cancel": {"it":"Annulla","es":"Cancelar","fr":"Annuler","de":"Abbrechen","pt-BR":"Cancelar","ja":"キャンセル","zh-Hans":"取消"},
 "Apply": {"it":"Applica","es":"Aplicar","fr":"Appliquer","de":"Anwenden","pt-BR":"Aplicar","ja":"適用","zh-Hans":"適用"},
 "Column %d": {"it":"Colonna %d","es":"Columna %d","fr":"Colonne %d","de":"Spalte %d","pt-BR":"Coluna %d","ja":"列%d","zh-Hans":"第 %d 列"},
 "Row %d, column %d": {"it":"Riga %d, colonna %d","es":"Fila %d, columna %d","fr":"Ligne %d, colonne %d","de":"Zeile %d, Spalte %d","pt-BR":"Linha %d, coluna %d","ja":"%d行%d列","zh-Hans":"第 %d 行，第 %d 列"},
 "Link": {"it":"Collegamento","es":"Enlace","fr":"Lien","de":"Link","pt-BR":"Link","ja":"リンク","zh-Hans":"链接"},
 "Link…": {"it":"Collegamento…","es":"Enlace…","fr":"Lien…","de":"Link…","pt-BR":"Link…","ja":"リンク…","zh-Hans":"链接…"},
 "Image": {"it":"Immagine","es":"Imagen","fr":"Image","de":"Bild","pt-BR":"Imagem","ja":"画像","zh-Hans":"图像"},
 "Image…": {"it":"Immagine…","es":"Imagen…","fr":"Image…","de":"Bild…","pt-BR":"Imagem…","ja":"画像…","zh-Hans":"图像…"},
 "Insert": {"it":"Inserisci","es":"Insertar","fr":"Insérer","de":"Einfügen","pt-BR":"Inserir","ja":"挿入","zh-Hans":"插入"},
 "Choose an image to insert.": {"it":"Scegli un’immagine da inserire.","es":"Elige una imagen para insertar.","fr":"Choisissez une image à insérer.","de":"Wähle ein Bild zum Einfügen aus.","pt-BR":"Escolha uma imagem para inserir.","ja":"挿入する画像を選択してください。","zh-Hans":"选择要插入的图像。"},
 "Horizontal Rule": {"it":"Linea orizzontale","es":"Línea horizontal","fr":"Ligne horizontale","de":"Horizontale Linie","pt-BR":"Linha Horizontal","ja":"水平線","zh-Hans":"水平线"},

 "View": {"it":"Vista","es":"Visualización","fr":"Présentation","de":"Darstellung","pt-BR":"Visualizar","ja":"表示","zh-Hans":"显示"},
 "Increase Text Size": {"it":"Aumenta dimensione testo","es":"Aumentar tamaño del texto","fr":"Augmenter la taille du texte","de":"Textgröße erhöhen","pt-BR":"Aumentar tamanho do texto","ja":"文字を大きくする","zh-Hans":"增大文字大小"},
 "Decrease Text Size": {"it":"Riduci dimensione testo","es":"Reducir tamaño del texto","fr":"Réduire la taille du texte","de":"Textgröße verringern","pt-BR":"Diminuir tamanho do texto","ja":"文字を小さくする","zh-Hans":"减小文字大小"},
 "Actual Text Size": {"it":"Dimensione testo originale","es":"Tamaño real del texto","fr":"Taille réelle du texte","de":"Tatsächliche Textgröße","pt-BR":"Tamanho real do texto","ja":"実際の文字サイズ","zh-Hans":"实际文字大小"},
 "Toggle Full Screen": {"it":"Attiva/disattiva schermo intero","es":"Activar/desactivar pantalla completa","fr":"Activer/désactiver le plein écran","de":"Vollbild ein/aus","pt-BR":"Ativar/Desativar Tela Cheia","ja":"フルスクリーンの切り替え","zh-Hans":"切换全屏幕"},
 "Window": {"it":"Finestra","es":"Ventana","fr":"Fenêtre","de":"Fenster","pt-BR":"Janela","ja":"ウインドウ","zh-Hans":"窗口"},
 "Minimize": {"it":"Riduci a icona","es":"Minimizar","fr":"Réduire","de":"Im Dock ablegen","pt-BR":"Minimizar","ja":"しまう","zh-Hans":"最小化"},
 "Zoom": {"it":"Zoom","es":"Zoom","fr":"Zoom","de":"Zoomen","pt-BR":"Zoom","ja":"拡大/縮小","zh-Hans":"缩放"},
 "Bring All to Front": {"it":"Porta tutto in primo piano","es":"Traer todo al frente","fr":"Tout ramener au premier plan","de":"Alle nach vorne bringen","pt-BR":"Trazer Tudo para a Frente","ja":"すべてを手前に移動","zh-Hans":"前置全部窗口"},

 "Choose the folder to work in.": {"it":"Scegli la cartella su cui lavorare.","es":"Elige la carpeta en la que trabajar.","fr":"Choisissez le dossier de travail.","de":"Wähle den Ordner, in dem du arbeiten möchtest.","pt-BR":"Escolha a pasta na qual trabalhar.","ja":"作業するフォルダを選択してください。","zh-Hans":"请选择要使用的文件夹。"},
 "Working folder": {"it":"Cartella di lavoro","es":"Carpeta de trabajo","fr":"Dossier de travail","de":"Arbeitsordner","pt-BR":"Pasta de trabalho","ja":"作業フォルダ","zh-Hans":"工作文件夹"},
 "Files in the working folder": {"it":"File della cartella di lavoro","es":"Archivos de la carpeta de trabajo","fr":"Fichiers du dossier de travail","de":"Dateien im Arbeitsordner","pt-BR":"Arquivos da pasta de trabalho","ja":"作業フォルダ内のファイル","zh-Hans":"工作文件夹中的文件"},
 "File actions": {"it":"Azioni file","es":"Acciones de archivo","fr":"Actions sur les fichiers","de":"Dateiaktionen","pt-BR":"Ações de arquivo","ja":"ファイル操作","zh-Hans":"文件操作"},
 "Open Working Folder in Finder": {"it":"Apri la cartella di lavoro nel Finder","es":"Abrir la carpeta de trabajo en Finder","fr":"Ouvrir le dossier de travail dans le Finder","de":"Arbeitsordner im Finder öffnen","pt-BR":"Abrir a pasta de trabalho no Finder","ja":"作業フォルダをFinderで開く","zh-Hans":"在访达中打开工作文件夹"},
 "Open Working Folder in Claude Cowork": {"it":"Apri la cartella di lavoro in Claude Cowork","es":"Abrir la carpeta de trabajo en Claude Cowork","fr":"Ouvrir le dossier de travail dans Claude Cowork","de":"Arbeitsordner in Claude Cowork öffnen","pt-BR":"Abrir a pasta de trabalho no Claude Cowork","ja":"作業フォルダをClaude Coworkで開く","zh-Hans":"在 Claude Cowork 中打开工作文件夹"},
 "Open Working Folder in ChatGPT": {"it":"Apri la cartella di lavoro in ChatGPT","es":"Abrir la carpeta de trabajo en ChatGPT","fr":"Ouvrir le dossier de travail dans ChatGPT","de":"Arbeitsordner in ChatGPT öffnen","pt-BR":"Abrir a pasta de trabalho no ChatGPT","ja":"作業フォルダをChatGPTで開く","zh-Hans":"在 ChatGPT 中打开工作文件夹"},
 "Choose the working folder": {"it":"Scegli la cartella di lavoro","es":"Elegir la carpeta de trabajo","fr":"Choisir le dossier de travail","de":"Arbeitsordner wählen","pt-BR":"Escolher a pasta de trabalho","ja":"作業フォルダを選択","zh-Hans":"选择工作文件夹"},
 "No Folder": {"it":"Nessuna cartella","es":"Sin carpeta","fr":"Aucun dossier","de":"Kein Ordner","pt-BR":"Nenhuma pasta","ja":"フォルダなし","zh-Hans":"无文件夹"},
 "Click the name above to choose a folder.": {"it":"Premi il nome qui sopra per scegliere una cartella.","es":"Haz clic en el nombre de arriba para elegir una carpeta.","fr":"Cliquez sur le nom ci-dessus pour choisir un dossier.","de":"Klicke oben auf den Namen, um einen Ordner zu wählen.","pt-BR":"Clique no nome acima para escolher uma pasta.","ja":"上の名前をクリックしてフォルダを選択します。","zh-Hans":"点按上方的名称以选择文件夹。"},
 "This folder contains no Markdown documents.": {"it":"Questa cartella non contiene documenti Markdown.","es":"Esta carpeta no contiene documentos Markdown.","fr":"Ce dossier ne contient aucun document Markdown.","de":"Dieser Ordner enthält keine Markdown-Dokumente.","pt-BR":"Esta pasta não contém documentos Markdown.","ja":"このフォルダにMarkdown書類はありません。","zh-Hans":"此文件夹中没有 Markdown 文稿。"},

 "text": {"it":"testo","es":"texto","fr":"texte","de":"Text","pt-BR":"texto","ja":"テキスト","zh-Hans":"文本"},
 "plain text": {"it":"testo normale","es":"texto normal","fr":"texte normal","de":"einfacher Text","pt-BR":"texto simples","ja":"標準テキスト","zh-Hans":"纯文本"},
 "[text](url)": {"it":"[testo](url)","es":"[texto](url)","fr":"[texte](url)","de":"[Text](URL)","pt-BR":"[texto](url)","ja":"[テキスト](url)","zh-Hans":"[文本](url)"},
 "![alt](path)": {"it":"![alt](percorso)","es":"![alt](ruta)","fr":"![alt](chemin)","de":"![alt](Pfad)","pt-BR":"![alt](caminho)","ja":"![alt](パス)","zh-Hans":"![alt](路径)"},

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
