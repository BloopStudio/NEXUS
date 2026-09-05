## I18n — Autoload singleton
## Lightweight in-code localization (no .csv/.po asset-import pipeline — the
## whole UI is already built in GDScript with no .tscn Control text to import
## against, so a plain lookup table keeps this self-contained and testable
## the same way as everything else in this project).
##
## Covers the highest-traffic screens first (main menu, HUD, settings,
## module names, phase labels) — the parts a player sees on every single
## match. Deeper/rarer text (class & spell flavor descriptions, mutator
## blurbs, skill-tree tier descriptions) is not yet in STRINGS and still
## shows its original French; add more keys here to extend coverage without
## touching how any of this is wired up.
extends Node

signal language_changed()

## Order here is what the Réglages dropdown shows.
const LANGUAGES := ["en", "fr", "es", "de", "it", "pt", "ru", "ja", "zh", "ar"]
const LANGUAGE_NAMES := {
	"en": "English", "fr": "Français", "es": "Español", "de": "Deutsch",
	"it": "Italiano", "pt": "Português", "ru": "Русский", "ja": "日本語",
	"zh": "中文", "ar": "العربية",
}

var current: String = "en"


func _ready() -> void:
	if SettingsManager.language != "":
		current = SettingsManager.language
	else:
		current = _detect_device_language()


## OS.get_locale_language() returns an ISO 639 code (e.g. "fr", "pt", "zh")
## that doesn't always match our list exactly (region variants, "pt_BR" etc.
## are already stripped by this call) — fall back to English for anything
## unsupported, per the requested default.
func _detect_device_language() -> String:
	var code := OS.get_locale_language()
	if code in LANGUAGES:
		return code
	return "en"


func set_language(code: String) -> void:
	if code == current or code not in LANGUAGES:
		return
	current = code
	SettingsManager.language = code
	SettingsManager.save_settings()
	language_changed.emit()


## Looks up `key`, falling back to English then to the key itself so a
## missing translation never shows a blank label.
func t(key: String) -> String:
	var entry: Dictionary = STRINGS.get(key, {})
	if entry.has(current):
		return entry[current]
	if entry.has("en"):
		return entry["en"]
	return key


func module_name(mtype: int) -> String:
	return t("module.%d.name" % mtype)


func module_icon(mtype: int) -> String:
	return ModuleInfo.ICONS[mtype] if mtype >= 0 and mtype < ModuleInfo.ICONS.size() else "?"


# ─── Strings ────────────────────────────────────────────────────────────────────
const STRINGS := {
	# Main menu
	"menu.subtitle": {"en": "Defend the station. Together.", "fr": "Defend the station. Together.", "es": "Defiende la estación. Juntos.", "de": "Verteidigt die Station. Gemeinsam.", "it": "Difendete la stazione. Insieme.", "pt": "Defenda a estação. Juntos.", "ru": "Защищайте станцию. Вместе.", "ja": "ステーションを守れ。共に。", "zh": "共同保卫空间站。", "ar": "دافعوا عن المحطة. معًا."},
	"menu.name_label": {"en": "Name: ", "fr": "Nom : ", "es": "Nombre: ", "de": "Name: ", "it": "Nome: ", "pt": "Nome: ", "ru": "Имя: ", "ja": "名前：", "zh": "名称：", "ar": "الاسم: "},
	"menu.class_label": {"en": "Class: ", "fr": "Classe : ", "es": "Clase: ", "de": "Klasse: ", "it": "Classe: ", "pt": "Classe: ", "ru": "Класс: ", "ja": "クラス：", "zh": "职业：", "ar": "الفئة: "},
	"menu.mutator_label": {"en": "Modifier (host): ", "fr": "Modificateur (hôte) : ", "es": "Modificador (anfitrión): ", "de": "Modifikator (Host): ", "it": "Modificatore (host): ", "pt": "Modificador (anfitrião): ", "ru": "Модификатор (хост): ", "ja": "修飾子（ホスト）：", "zh": "修饰符（房主）：", "ar": "المُعدِّل (المضيف): "},
	"menu.spells_label": {"en": "Spells (keys E / A):", "fr": "Sorts (touches E / A) :", "es": "Hechizos (teclas E / A):", "de": "Zauber (Tasten E / A):", "it": "Incantesimi (tasti E / A):", "pt": "Feitiços (teclas E / A):", "ru": "Заклинания (клавиши E / A):", "ja": "呪文（キー E / A）：", "zh": "法术（按键 E / A）：", "ar": "التعويذات (المفاتيح E / A):"},
	"menu.btn_host": {"en": "🛡  Host a game", "fr": "🛡  Héberger une partie", "es": "🛡  Alojar partida", "de": "🛡  Spiel hosten", "it": "🛡  Ospita partita", "pt": "🛡  Hospedar jogo", "ru": "🛡  Создать игру", "ja": "🛡  ゲームをホストする", "zh": "🛡  创建游戏", "ar": "🛡  استضافة لعبة"},
	"menu.btn_join": {"en": "🔗  Join with a code", "fr": "🔗  Rejoindre avec un code", "es": "🔗  Unirse con un código", "de": "🔗  Mit Code beitreten", "it": "🔗  Unisciti con un codice", "pt": "🔗  Entrar com um código", "ru": "🔗  Присоединиться по коду", "ja": "🔗  コードで参加", "zh": "🔗  使用代码加入", "ar": "🔗  الانضمام برمز"},
	"menu.btn_solo": {"en": "🤖  Solo (local test)", "fr": "🤖  Solo (test local)", "es": "🤖  Solo (prueba local)", "de": "🤖  Solo (lokaler Test)", "it": "🤖  Solo (test locale)", "pt": "🤖  Solo (teste local)", "ru": "🤖  Соло (локальный тест)", "ja": "🤖  ソロ（ローカルテスト）", "zh": "🤖  单人（本地测试）", "ar": "🤖  فردي (اختبار محلي)"},
	"menu.btn_settings": {"en": "⚙  Settings", "fr": "⚙  Réglages", "es": "⚙  Ajustes", "de": "⚙  Einstellungen", "it": "⚙  Impostazioni", "pt": "⚙  Definições", "ru": "⚙  Настройки", "ja": "⚙  設定", "zh": "⚙  设置", "ar": "⚙  الإعدادات"},
	"menu.btn_scores": {"en": "🏆  Leaderboard", "fr": "🏆  Classement", "es": "🏆  Clasificación", "de": "🏆  Bestenliste", "it": "🏆  Classifica", "pt": "🏆  Classificação", "ru": "🏆  Таблица рекордов", "ja": "🏆  ランキング", "zh": "🏆  排行榜", "ar": "🏆  لوحة المتصدرين"},
	"menu.btn_quit": {"en": "✕  Quit game", "fr": "✕  Quitter", "es": "✕  Salir", "de": "✕  Beenden", "it": "✕  Esci", "pt": "✕  Sair", "ru": "✕  Выход", "ja": "✕  終了", "zh": "✕  退出", "ar": "✕  خروج"},
	"menu.btn_start": {"en": "▶  Start match", "fr": "▶  Démarrer la partie", "es": "▶  Iniciar partida", "de": "▶  Spiel starten", "it": "▶  Avvia partita", "pt": "▶  Iniciar jogo", "ru": "▶  Начать игру", "ja": "▶  試合開始", "zh": "▶  开始游戏", "ar": "▶  بدء المباراة"},
	"menu.btn_connect": {"en": "🔌  Connect", "fr": "🔌  Se connecter", "es": "🔌  Conectar", "de": "🔌  Verbinden", "it": "🔌  Connetti", "pt": "🔌  Ligar", "ru": "🔌  Подключиться", "ja": "🔌  接続", "zh": "🔌  连接", "ar": "🔌  اتصال"},
	"menu.code_hint": {"en": "Click to copy", "fr": "Cliquer pour copier", "es": "Clic para copiar", "de": "Zum Kopieren klicken", "it": "Clicca per copiare", "pt": "Clique para copiar", "ru": "Нажмите, чтобы скопировать", "ja": "クリックでコピー", "zh": "点击复制", "ar": "انقر للنسخ"},
	"menu.code_label": {"en": "Party code (click to copy):", "fr": "Code de partie (clique dessus pour le copier) :", "es": "Código de partida (haz clic para copiarlo):", "de": "Party-Code (zum Kopieren klicken):", "it": "Codice partita (clicca per copiarlo):", "pt": "Código da partida (clique para copiar):", "ru": "Код игры (нажмите, чтобы скопировать):", "ja": "パーティコード（クリックでコピー）：", "zh": "队伍代码（点击复制）：", "ar": "رمز الفريق (انقر للنسخ):"},
	"menu.join_label": {"en": "Enter the party code:", "fr": "Entre le code de partie :", "es": "Introduce el código de partida:", "de": "Party-Code eingeben:", "it": "Inserisci il codice partita:", "pt": "Insira o código da partida:", "ru": "Введите код игры:", "ja": "パーティコードを入力：", "zh": "输入队伍代码：", "ar": "أدخل رمز الفريق:"},
	"menu.join_code_placeholder": {"en": "Base64 code...", "fr": "Code Base64...", "es": "Código Base64...", "de": "Base64-Code...", "it": "Codice Base64...", "pt": "Código Base64...", "ru": "Код Base64...", "ja": "Base64コード...", "zh": "Base64 代码…", "ar": "رمز Base64..."},
	"menu.lobby_label": {"en": "Players in the match:", "fr": "Joueurs dans la partie :", "es": "Jugadores en la partida:", "de": "Spieler im Match:", "it": "Giocatori nella partita:", "pt": "Jogadores na partida:", "ru": "Игроки в матче:", "ja": "試合中のプレイヤー：", "zh": "对局中的玩家：", "ar": "اللاعبون في المباراة:"},
	"menu.scores_empty": {"en": "No hosted match yet.", "fr": "Aucune partie hébergée pour l'instant.", "es": "Aún no hay partidas alojadas.", "de": "Noch kein gehostetes Match.", "it": "Nessuna partita ospitata ancora.", "pt": "Ainda nenhum jogo hospedado.", "ru": "Пока нет размещённых игр.", "ja": "まだホストした試合がありません。", "zh": "尚未创建过对局。", "ar": "لا توجد مباراة مستضافة بعد."},
	"menu.scores_header": {"en": "Best waves reached (matches hosted here):", "fr": "Meilleures vagues atteintes (parties hébergées ici) :", "es": "Mejores oleadas alcanzadas (partidas alojadas aquí):", "de": "Beste erreichte Wellen (hier gehostete Matches):", "it": "Migliori ondate raggiunte (partite ospitate qui):", "pt": "Melhores vagas alcançadas (jogos hospedados aqui):", "ru": "Лучшие достигнутые волны (игры, размещённые здесь):", "ja": "到達した最高ウェーブ（このPCでホストした試合）：", "zh": "达到的最高波数（本机创建的对局）：", "ar": "أفضل الموجات التي تم الوصول إليها (المباريات المستضافة هنا):"},
	"hud.host_tag": {"en": "  👑 host", "fr": "  👑 hôte", "es": "  👑 anfitrión", "de": "  👑 Host", "it": "  👑 host", "pt": "  👑 anfitrião", "ru": "  👑 хост", "ja": "  👑 ホスト", "zh": "  👑 房主", "ar": "  👑 المضيف"},
	"menu.you_tag": {"en": " (you)", "fr": " (toi)", "es": " (tú)", "de": " (du)", "it": " (tu)", "pt": " (tu)", "ru": " (вы)", "ja": "（あなた）", "zh": "（你）", "ar": " (أنت)"},
	"menu.default_player_name": {"en": "Player", "fr": "Joueur", "es": "Jugador", "de": "Spieler", "it": "Giocatore", "pt": "Jogador", "ru": "Игрок", "ja": "プレイヤー", "zh": "玩家", "ar": "اللاعب"},
	"menu.join_note": {"en": "ℹ  The code the host gives you is usually enough — no network setup needed in most cases.", "fr": "ℹ  Le code fourni par l'hôte suffit — aucune manip réseau n'est nécessaire dans la grande majorité des cas.", "es": "ℹ  El código que te da el anfitrión suele bastar — normalmente no hace falta configurar la red.", "de": "ℹ  Der Code vom Host reicht meist aus — in den meisten Fällen ist keine Netzwerkeinrichtung nötig.", "it": "ℹ  Il codice fornito dall'host di solito basta — nella maggior parte dei casi non serve alcuna configurazione di rete.", "pt": "ℹ  O código do anfitrião costuma bastar — na maioria dos casos não é preciso configurar a rede.", "ru": "ℹ  Обычно достаточно кода от хоста — в большинстве случаев настройка сети не требуется.", "ja": "ℹ  ホストのコードだけで十分な場合がほとんどです — 通常はネットワーク設定は不要です。", "zh": "ℹ  房主提供的代码通常就够了——大多数情况下无需任何网络设置。", "ar": "ℹ  عادةً يكفي الرمز الذي يعطيك إياه المضيف — لا حاجة لإعداد الشبكة في معظم الحالات."},

	# Main menu — status messages
	"status.port_error": {"en": "Error: couldn't open port 7777.", "fr": "Erreur : impossible d'ouvrir le port 7777.", "es": "Error: no se pudo abrir el puerto 7777.", "de": "Fehler: Port 7777 konnte nicht geöffnet werden.", "it": "Errore: impossibile aprire la porta 7777.", "pt": "Erro: não foi possível abrir a porta 7777.", "ru": "Ошибка: не удалось открыть порт 7777.", "ja": "エラー：ポート7777を開けませんでした。", "zh": "错误：无法打开端口 7777。", "ar": "خطأ: تعذّر فتح المنفذ 7777."},
	"status.opening_port": {"en": "Opening the port automatically…", "fr": "Ouverture automatique du port…", "es": "Abriendo el puerto automáticamente…", "de": "Port wird automatisch geöffnet…", "it": "Apertura automatica della porta…", "pt": "A abrir a porta automaticamente…", "ru": "Автоматическое открытие порта…", "ja": "ポートを自動的に開いています…", "zh": "正在自动打开端口…", "ar": "جارٍ فتح المنفذ تلقائيًا…"},
	"status.ready_upnp": {"en": "Ready! Just share the code — nothing else needed.", "fr": "Prêt ! Partage juste le code — aucune manip requise.", "es": "¡Listo! Solo comparte el código — no se necesita nada más.", "de": "Bereit! Teile einfach den Code — nichts weiter nötig.", "it": "Pronto! Condividi semplicemente il codice — non serve altro.", "pt": "Pronto! Basta partilhar o código — nada mais é necessário.", "ru": "Готово! Просто поделитесь кодом — больше ничего не нужно.", "ja": "準備完了！コードを共有するだけで大丈夫です。", "zh": "准备就绪！只需分享代码即可，无需其他操作。", "ar": "جاهز! ما عليك سوى مشاركة الرمز — لا حاجة لأي شيء آخر."},
	"status.ready_stun": {"en": "Port wasn't opened automatically, but an alternate address was found — the code should still have a good chance of working.", "fr": "Port non ouvert automatiquement, mais une adresse alternative a été trouvée — le code a de bonnes chances de fonctionner quand même.", "es": "El puerto no se abrió automáticamente, pero se encontró una dirección alternativa — el código debería tener buenas posibilidades de funcionar igualmente.", "de": "Port wurde nicht automatisch geöffnet, aber eine alternative Adresse wurde gefunden — der Code sollte trotzdem gute Chancen haben zu funktionieren.", "it": "La porta non è stata aperta automaticamente, ma è stato trovato un indirizzo alternativo — il codice ha comunque buone probabilità di funzionare.", "pt": "A porta não foi aberta automaticamente, mas foi encontrado um endereço alternativo — o código deve ter boas hipóteses de funcionar mesmo assim.", "ru": "Порт не был открыт автоматически, но найден альтернативный адрес — код всё равно, скорее всего, сработает.", "ja": "ポートは自動的に開けませんでしたが、代替アドレスが見つかりました — コードはそれでも機能する可能性が高いです。", "zh": "端口未能自动打开，但找到了备用地址——代码仍有较大概率可用。", "ar": "لم يتم فتح المنفذ تلقائيًا، لكن تم العثور على عنوان بديل — لا يزال من المحتمل أن يعمل الرمز."},
	"status.no_upnp_no_stun": {"en": "Router doesn't support UPnP and no reachable address was found: the code will only work on the host's local network unless you open port 7777 (UDP) yourself.", "fr": "Routeur incompatible UPnP et adresse non joignable détectée : le code ne marchera qu'en réseau local, sauf si tu ouvres le port 7777 (UDP) toi-même.", "es": "El router no admite UPnP y no se encontró una dirección accesible: el código solo funcionará en la red local del anfitrión, a menos que abras tú mismo el puerto 7777 (UDP).", "de": "Router unterstützt kein UPnP, und keine erreichbare Adresse gefunden: Der Code funktioniert nur im lokalen Netzwerk des Hosts, außer du öffnest Port 7777 (UDP) selbst.", "it": "Il router non supporta UPnP e non è stato trovato un indirizzo raggiungibile: il codice funzionerà solo sulla rete locale dell'host, a meno che tu non apra tu stesso la porta 7777 (UDP).", "pt": "O router não é compatível com UPnP e não foi encontrado um endereço acessível: o código só funcionará na rede local do anfitrião, a menos que abras tu mesmo a porta 7777 (UDP).", "ru": "Роутер не поддерживает UPnP, и доступный адрес не найден: код будет работать только в локальной сети хоста, если вы сами не откроете порт 7777 (UDP).", "ja": "ルーターがUPnPに対応しておらず、到達可能なアドレスも見つかりませんでした：自分でポート7777（UDP）を開かない限り、コードはホストのローカルネットワークでしか機能しません。", "zh": "路由器不支持 UPnP，且未找到可达地址：除非你自己打开端口 7777（UDP），否则该代码只能在房主的局域网内使用。", "ar": "الموجّه لا يدعم UPnP ولم يُعثر على عنوان يمكن الوصول إليه: لن يعمل الرمز إلا على الشبكة المحلية للمضيف، إلا إذا قمت بفتح المنفذ 7777 (UDP) بنفسك."},
	"status.code_copied": {"en": "Code copied to clipboard!", "fr": "Code copié dans le presse-papiers !", "es": "¡Código copiado al portapapeles!", "de": "Code in die Zwischenablage kopiert!", "it": "Codice copiato negli appunti!", "pt": "Código copiado para a área de transferência!", "ru": "Код скопирован в буфер обмена!", "ja": "コードをクリップボードにコピーしました！", "zh": "代码已复制到剪贴板！", "ar": "تم نسخ الرمز إلى الحافظة!"},
	"status.waiting_player": {"en": "Waiting for at least one player…", "fr": "En attente d'au moins un joueur…", "es": "Esperando al menos a un jugador…", "de": "Warte auf mindestens einen Spieler…", "it": "In attesa di almeno un giocatore…", "pt": "A aguardar pelo menos um jogador…", "ru": "Ожидание хотя бы одного игрока…", "ja": "少なくとも1人のプレイヤーを待っています…", "zh": "等待至少一名玩家加入…", "ar": "في انتظار لاعب واحد على الأقل…"},
	"status.enter_code": {"en": "Enter a party code.", "fr": "Entre un code de partie.", "es": "Introduce un código de partida.", "de": "Gib einen Party-Code ein.", "it": "Inserisci un codice partita.", "pt": "Insere um código de partida.", "ru": "Введите код игры.", "ja": "パーティコードを入力してください。", "zh": "请输入队伍代码。", "ar": "أدخل رمز الفريق."},
	"status.connecting": {"en": "Connecting…", "fr": "Connexion en cours…", "es": "Conectando…", "de": "Verbindung wird hergestellt…", "it": "Connessione in corso…", "pt": "A ligar…", "ru": "Подключение…", "ja": "接続中…", "zh": "连接中…", "ar": "جارٍ الاتصال…"},
	"status.connecting_attempt": {"en": "Connecting… (attempt %d/%d)", "fr": "Connexion en cours… (essai %d/%d)", "es": "Conectando… (intento %d/%d)", "de": "Verbindung wird hergestellt… (Versuch %d/%d)", "it": "Connessione in corso… (tentativo %d/%d)", "pt": "A ligar… (tentativa %d/%d)", "ru": "Подключение… (попытка %d/%d)", "ja": "接続中…（試行 %d/%d）", "zh": "连接中…（第 %d/%d 次尝试）", "ar": "جارٍ الاتصال… (المحاولة %d/%d)"},
	"status.invalid_code": {"en": "Invalid code.", "fr": "Code invalide.", "es": "Código no válido.", "de": "Ungültiger Code.", "it": "Codice non valido.", "pt": "Código inválido.", "ru": "Неверный код.", "ja": "無効なコードです。", "zh": "代码无效。", "ar": "رمز غير صالح."},
	"status.connected": {"en": "Connected! Waiting for the match to start…", "fr": "Connecté ! En attente du démarrage…", "es": "¡Conectado! Esperando a que comience la partida…", "de": "Verbunden! Warte auf Spielstart…", "it": "Connesso! In attesa dell'inizio della partita…", "pt": "Ligado! A aguardar o início do jogo…", "ru": "Подключено! Ожидание начала игры…", "ja": "接続しました！試合開始を待っています…", "zh": "已连接！等待对局开始…", "ar": "تم الاتصال! في انتظار بدء المباراة…"},
	"status.connection_failed": {"en": "Connection failed (timed out). Check the code, or the host may not be reachable from the internet (firewall, or a router/CGNAT setup — in that case only the host's local network can connect).", "fr": "Connexion échouée (délai dépassé). Vérifie le code, ou l'hôte n'est pas joignable depuis internet (pare-feu, ou routeur/box en CGNAT — dans ce cas, seul le réseau local de l'hôte peut se connecter).", "es": "Conexión fallida (tiempo agotado). Comprueba el código, o puede que el anfitrión no sea accesible desde internet (cortafuegos, o router/CGNAT — en ese caso, solo la red local del anfitrión puede conectarse).", "de": "Verbindung fehlgeschlagen (Zeitüberschreitung). Überprüfe den Code, oder der Host ist eventuell nicht aus dem Internet erreichbar (Firewall oder Router/CGNAT — in diesem Fall kann sich nur das lokale Netzwerk des Hosts verbinden).", "it": "Connessione non riuscita (timeout). Controlla il codice, oppure l'host potrebbe non essere raggiungibile da internet (firewall, o router/CGNAT — in tal caso può connettersi solo la rete locale dell'host).", "pt": "Falha na ligação (tempo esgotado). Verifica o código, ou o anfitrião pode não estar acessível pela internet (firewall, ou router/CGNAT — nesse caso, só a rede local do anfitrião consegue ligar-se).", "ru": "Не удалось подключиться (истекло время ожидания). Проверьте код, либо хост недоступен из интернета (файрвол, или роутер/CGNAT — в этом случае подключиться может только локальная сеть хоста).", "ja": "接続に失敗しました（タイムアウト）。コードを確認するか、ホストがインターネットから到達できない可能性があります（ファイアウォール、またはルーター/CGNAT — その場合、ホストのローカルネットワークからのみ接続できます）。", "zh": "连接失败（超时）。请检查代码，或者房主可能无法从互联网访问（防火墙，或路由器/CGNAT——这种情况下只有房主的局域网可以连接）。", "ar": "فشل الاتصال (انتهت المهلة). تحقق من الرمز، أو قد يكون المضيف غير قابل للوصول من الإنترنت (جدار حماية، أو موجّه/CGNAT — في هذه الحالة يمكن فقط للشبكة المحلية للمضيف الاتصال)."},
	"status.score_row": {"en": "%d. %s — Wave %d (%s)", "fr": "%d. %s — Vague %d (%s)", "es": "%d. %s — Oleada %d (%s)", "de": "%d. %s — Welle %d (%s)", "it": "%d. %s — Ondata %d (%s)", "pt": "%d. %s — Vaga %d (%s)", "ru": "%d. %s — Волна %d (%s)", "ja": "%d. %s — ウェーブ %d（%s）", "zh": "%d. %s — 第 %d 波（%s）", "ar": "%d. %s — الموجة %d (%s)"},

	# Settings menu
	"settings.title": {"en": "SETTINGS", "fr": "RÉGLAGES", "es": "AJUSTES", "de": "EINSTELLUNGEN", "it": "IMPOSTAZIONI", "pt": "DEFINIÇÕES", "ru": "НАСТРОЙКИ", "ja": "設定", "zh": "设置", "ar": "الإعدادات"},
	"settings.tab_controls": {"en": "Controls", "fr": "Contrôles", "es": "Controles", "de": "Steuerung", "it": "Controlli", "pt": "Controlos", "ru": "Управление", "ja": "操作", "zh": "操作", "ar": "التحكم"},
	"settings.tab_graphics": {"en": "Graphics", "fr": "Graphismes", "es": "Gráficos", "de": "Grafik", "it": "Grafica", "pt": "Gráficos", "ru": "Графика", "ja": "グラフィック", "zh": "画面", "ar": "الرسومات"},
	"settings.tab_audio": {"en": "Audio", "fr": "Son", "es": "Sonido", "de": "Audio", "it": "Audio", "pt": "Áudio", "ru": "Звук", "ja": "サウンド", "zh": "音效", "ar": "الصوت"},
	"settings.tab_language": {"en": "Language", "fr": "Langue", "es": "Idioma", "de": "Sprache", "it": "Lingua", "pt": "Idioma", "ru": "Язык", "ja": "言語", "zh": "语言", "ar": "اللغة"},
	"settings.language_label": {"en": "Game language:", "fr": "Langue du jeu :", "es": "Idioma del juego:", "de": "Spielsprache:", "it": "Lingua del gioco:", "pt": "Idioma do jogo:", "ru": "Язык игры:", "ja": "ゲーム言語：", "zh": "游戏语言：", "ar": "لغة اللعبة:"},
	"settings.language_note": {"en": "Detected automatically from your device on first launch. Some rarer text may still show in French.", "fr": "Détectée automatiquement à partir de ton appareil au premier lancement. Certains textes plus rares peuvent encore s'afficher en français.", "es": "Detectado automáticamente desde tu dispositivo en el primer inicio. Parte del texto menos frecuente puede seguir en francés.", "de": "Wird beim ersten Start automatisch anhand deines Geräts erkannt. Manche selteneren Texte werden evtl. noch auf Französisch angezeigt.", "it": "Rilevata automaticamente dal tuo dispositivo al primo avvio. Alcuni testi più rari potrebbero ancora apparire in francese.", "pt": "Detetado automaticamente a partir do teu dispositivo no primeiro arranque. Alguns textos mais raros podem ainda aparecer em francês.", "ru": "Определяется автоматически по вашему устройству при первом запуске. Часть редких текстов может по-прежнему отображаться на французском.", "ja": "初回起動時に端末から自動検出されます。一部の珍しいテキストはまだフランス語で表示される場合があります。", "zh": "首次启动时会根据设备自动检测。部分较少见的文本可能仍显示为法语。", "ar": "يتم اكتشافها تلقائيًا من جهازك عند أول تشغيل. قد يظل بعض النصوص النادرة معروضًا بالفرنسية."},
	"settings.fullscreen": {"en": "Fullscreen", "fr": "Plein écran", "es": "Pantalla completa", "de": "Vollbild", "it": "Schermo intero", "pt": "Ecrã inteiro", "ru": "Полный экран", "ja": "フルスクリーン", "zh": "全屏", "ar": "ملء الشاشة"},
	"settings.vsync": {"en": "V-Sync", "fr": "V-Sync", "es": "V-Sync", "de": "V-Sync", "it": "V-Sync", "pt": "V-Sync", "ru": "V-Sync", "ja": "V-Sync", "zh": "垂直同步", "ar": "V-Sync"},
	"settings.resolution": {"en": "Windowed resolution", "fr": "Résolution fenêtrée", "es": "Resolución en ventana", "de": "Fensterauflösung", "it": "Risoluzione finestra", "pt": "Resolução em janela", "ru": "Разрешение в окне", "ja": "ウィンドウ解像度", "zh": "窗口分辨率", "ar": "دقة النافذة"},
	"settings.show_fps": {"en": "Show FPS", "fr": "Afficher les FPS", "es": "Mostrar FPS", "de": "FPS anzeigen", "it": "Mostra FPS", "pt": "Mostrar FPS", "ru": "Показывать FPS", "ja": "FPSを表示", "zh": "显示帧率", "ar": "إظهار FPS"},
	"settings.fps_limit": {"en": "FPS limit", "fr": "Limite de FPS", "es": "Límite de FPS", "de": "FPS-Limit", "it": "Limite FPS", "pt": "Limite de FPS", "ru": "Ограничение FPS", "ja": "FPS上限", "zh": "帧率上限", "ar": "حد FPS"},
	"settings.fps_unlimited": {"en": "Unlimited", "fr": "Illimitée", "es": "Ilimitado", "de": "Unbegrenzt", "it": "Illimitato", "pt": "Ilimitado", "ru": "Без ограничений", "ja": "無制限", "zh": "无限制", "ar": "غير محدود"},
	"settings.volume_master": {"en": "Master", "fr": "Général", "es": "General", "de": "Gesamt", "it": "Generale", "pt": "Geral", "ru": "Общая", "ja": "全体", "zh": "主音量", "ar": "الرئيسي"},
	"settings.volume_music": {"en": "Music", "fr": "Musique", "es": "Música", "de": "Musik", "it": "Musica", "pt": "Música", "ru": "Музыка", "ja": "音楽", "zh": "音乐", "ar": "الموسيقى"},
	"settings.volume_sfx": {"en": "Sound effects", "fr": "Effets sonores", "es": "Efectos de sonido", "de": "Soundeffekte", "it": "Effetti sonori", "pt": "Efeitos sonoros", "ru": "Звуковые эффекты", "ja": "効果音", "zh": "音效", "ar": "المؤثرات الصوتية"},
	"settings.close": {"en": "Close", "fr": "Fermer", "es": "Cerrar", "de": "Schließen", "it": "Chiudi", "pt": "Fechar", "ru": "Закрыть", "ja": "閉じる", "zh": "关闭", "ar": "إغلاق"},
	"settings.controls_hint": {"en": "Click a key then press the new key/button.", "fr": "Clique sur une touche puis appuie sur la nouvelle touche/bouton.", "es": "Haz clic en una tecla y luego pulsa la nueva tecla/botón.", "de": "Klicke auf eine Taste und drücke dann die neue Taste/den neuen Knopf.", "it": "Clicca su un tasto poi premi il nuovo tasto/pulsante.", "pt": "Clica numa tecla e depois carrega na nova tecla/botão.", "ru": "Нажмите на клавишу, затем нажмите новую клавишу/кнопку.", "ja": "キーをクリックしてから新しいキー/ボタンを押してください。", "zh": "点击一个按键，然后按下新的按键/按钮。", "ar": "انقر على مفتاح ثم اضغط على المفتاح/الزر الجديد."},
	"settings.press_key": {"en": "Press a key…", "fr": "Appuie sur une touche…", "es": "Pulsa una tecla…", "de": "Taste drücken…", "it": "Premi un tasto…", "pt": "Carrega numa tecla…", "ru": "Нажмите клавишу…", "ja": "キーを押してください…", "zh": "请按键…", "ar": "اضغط على مفتاح…"},
	"action.move_up": {"en": "Move up", "fr": "Avancer", "es": "Avanzar", "de": "Vorwärts", "it": "Avanti", "pt": "Avançar", "ru": "Вперёд", "ja": "前進", "zh": "前进", "ar": "التقدم"},
	"action.move_down": {"en": "Move down", "fr": "Reculer", "es": "Retroceder", "de": "Rückwärts", "it": "Indietro", "pt": "Recuar", "ru": "Назад", "ja": "後退", "zh": "后退", "ar": "التراجع"},
	"action.move_left": {"en": "Move left", "fr": "Aller à gauche", "es": "Ir a la izquierda", "de": "Nach links", "it": "Vai a sinistra", "pt": "Ir para a esquerda", "ru": "Влево", "ja": "左に進む", "zh": "向左", "ar": "الاتجاه لليسار"},
	"action.move_right": {"en": "Move right", "fr": "Aller à droite", "es": "Ir a la derecha", "de": "Nach rechts", "it": "Vai a destra", "pt": "Ir para a direita", "ru": "Вправо", "ja": "右に進む", "zh": "向右", "ar": "الاتجاه لليمين"},
	"action.shoot": {"en": "Shoot", "fr": "Tirer", "es": "Disparar", "de": "Schießen", "it": "Spara", "pt": "Disparar", "ru": "Стрелять", "ja": "撃つ", "zh": "射击", "ar": "إطلاق النار"},
	"action.ability": {"en": "Spell (slot 1)", "fr": "Sort (emplacement 1)", "es": "Hechizo (ranura 1)", "de": "Zauber (Slot 1)", "it": "Incantesimo (slot 1)", "pt": "Feitiço (ranhura 1)", "ru": "Заклинание (слот 1)", "ja": "呪文（スロット1）", "zh": "法术（栏位1）", "ar": "تعويذة (الخانة 1)"},
	"action.ability_2": {"en": "Spell (slot 2)", "fr": "Sort (emplacement 2)", "es": "Hechizo (ranura 2)", "de": "Zauber (Slot 2)", "it": "Incantesimo (slot 2)", "pt": "Feitiço (ranhura 2)", "ru": "Заклинание (слот 2)", "ja": "呪文（スロット2）", "zh": "法术（栏位2）", "ar": "تعويذة (الخانة 2)"},
	"action.ping_focus": {"en": "Ping: focus here", "fr": "Marqueur : Focus ici", "es": "Marcador: Enfocar aquí", "de": "Markierung: Hier fokussieren", "it": "Indicatore: Concentrati qui", "pt": "Marcador: Focar aqui", "ru": "Метка: сосредоточиться здесь", "ja": "ピン：ここに集中", "zh": "标记：集火此处", "ar": "إشارة: التركيز هنا"},
	"action.ping_help": {"en": "Ping: need help", "fr": "Marqueur : Besoin d'aide", "es": "Marcador: Necesito ayuda", "de": "Markierung: Brauche Hilfe", "it": "Indicatore: Serve aiuto", "pt": "Marcador: Preciso de ajuda", "ru": "Метка: нужна помощь", "ja": "ピン：助けが必要", "zh": "标记：需要帮助", "ar": "إشارة: بحاجة إلى مساعدة"},
	"input.mouse_left": {"en": "Left click", "fr": "Clic gauche", "es": "Clic izquierdo", "de": "Linksklick", "it": "Clic sinistro", "pt": "Clique esquerdo", "ru": "ЛКМ", "ja": "左クリック", "zh": "左键点击", "ar": "نقرة يسرى"},
	"input.mouse_right": {"en": "Right click", "fr": "Clic droit", "es": "Clic derecho", "de": "Rechtsklick", "it": "Clic destro", "pt": "Clique direito", "ru": "ПКМ", "ja": "右クリック", "zh": "右键点击", "ar": "نقرة يمنى"},
	"input.mouse_middle": {"en": "Middle click", "fr": "Clic molette", "es": "Clic central", "de": "Mittelklick", "it": "Clic centrale", "pt": "Clique do meio", "ru": "СКМ", "ja": "中央クリック", "zh": "中键点击", "ar": "نقرة وسطى"},
	"input.mouse_button": {"en": "Mouse button %d", "fr": "Bouton souris %d", "es": "Botón del ratón %d", "de": "Maustaste %d", "it": "Pulsante del mouse %d", "pt": "Botão do rato %d", "ru": "Кнопка мыши %d", "ja": "マウスボタン%d", "zh": "鼠标按钮 %d", "ar": "زر الفأرة %d"},

	# HUD
	"hud.energy": {"en": "ENERGY: %d", "fr": "ÉNERGIE: %d", "es": "ENERGÍA: %d", "de": "ENERGIE: %d", "it": "ENERGIA: %d", "pt": "ENERGIA: %d", "ru": "ЭНЕРГИЯ: %d", "ja": "エネルギー: %d", "zh": "能量: %d", "ar": "الطاقة: %d"},
	"hud.materials": {"en": "⛏ MATERIALS: %d", "fr": "⛏ MATÉRIAUX: %d", "es": "⛏ MATERIALES: %d", "de": "⛏ MATERIAL: %d", "it": "⛏ MATERIALI: %d", "pt": "⛏ MATERIAIS: %d", "ru": "⛏ МАТЕРИАЛЫ: %d", "ja": "⛏ 資材: %d", "zh": "⛏ 材料: %d", "ar": "⛏ المواد: %d"},
	"hud.wave": {"en": "WAVE %d", "fr": "VAGUE %d", "es": "OLEADA %d", "de": "WELLE %d", "it": "ONDATA %d", "pt": "VAGA %d", "ru": "ВОЛНА %d", "ja": "ウェーブ %d", "zh": "第 %d 波", "ar": "الموجة %d"},
	"hud.station": {"en": "STATION %d/%d", "fr": "STATION %d/%d", "es": "ESTACIÓN %d/%d", "de": "STATION %d/%d", "it": "STAZIONE %d/%d", "pt": "ESTAÇÃO %d/%d", "ru": "СТАНЦИЯ %d/%d", "ja": "ステーション %d/%d", "zh": "空间站 %d/%d", "ar": "المحطة %d/%d"},
	"hud.settings": {"en": "⚙ Settings", "fr": "⚙ Réglages", "es": "⚙ Ajustes", "de": "⚙ Einstellungen", "it": "⚙ Impostazioni", "pt": "⚙ Definições", "ru": "⚙ Настройки", "ja": "⚙ 設定", "zh": "⚙ 设置", "ar": "⚙ الإعدادات"},
	"hud.quit": {"en": "✕ Quit", "fr": "✕ Quitter", "es": "✕ Salir", "de": "✕ Verlassen", "it": "✕ Esci", "pt": "✕ Sair", "ru": "✕ Выйти", "ja": "✕ 退出", "zh": "✕ 退出", "ar": "✕ خروج"},
	"hud.level_max": {"en": "MAX Lv.", "fr": "Nv. MAX", "es": "Niv. MÁX", "de": "Max. Stufe", "it": "Liv. MAX", "pt": "Nív. MÁX", "ru": "Макс. ур.", "ja": "最大Lv", "zh": "最高等级", "ar": "أقصى مستوى"},

	# Phases
	"phase.build": {"en": "BUILD", "fr": "CONSTRUCTION", "es": "CONSTRUCCIÓN", "de": "BAUEN", "it": "COSTRUZIONE", "pt": "CONSTRUÇÃO", "ru": "СТРОИТЕЛЬСТВО", "ja": "建設", "zh": "建造", "ar": "البناء"},
	"phase.wave": {"en": "WAVE", "fr": "VAGUE", "es": "OLEADA", "de": "WELLE", "it": "ONDATA", "pt": "VAGA", "ru": "ВОЛНА", "ja": "ウェーブ", "zh": "波次", "ar": "الموجة"},

	# Module names (module.<ModuleType index>.name — see game_state.gd's enum)
	"module.0.name": {"en": "Empty", "fr": "Vide", "es": "Vacío", "de": "Leer", "it": "Vuoto", "pt": "Vazio", "ru": "Пусто", "ja": "空", "zh": "空", "ar": "فارغ"},
	"module.1.name": {"en": "Generator", "fr": "Générateur", "es": "Generador", "de": "Generator", "it": "Generatore", "pt": "Gerador", "ru": "Генератор", "ja": "発電機", "zh": "发电机", "ar": "مولد"},
	"module.2.name": {"en": "Turret", "fr": "Tourelle", "es": "Torreta", "de": "Geschützturm", "it": "Torretta", "pt": "Torreta", "ru": "Турель", "ja": "タレット", "zh": "炮塔", "ar": "برج مدفعي"},
	"module.3.name": {"en": "Shield", "fr": "Bouclier", "es": "Escudo", "de": "Schild", "it": "Scudo", "pt": "Escudo", "ru": "Щит", "ja": "シールド", "zh": "护盾", "ar": "درع"},
	"module.4.name": {"en": "Repair", "fr": "Réparation", "es": "Reparación", "de": "Reparatur", "it": "Riparazione", "pt": "Reparação", "ru": "Ремонт", "ja": "修理", "zh": "维修", "ar": "إصلاح"},
	"module.5.name": {"en": "Booster", "fr": "Amplificateur", "es": "Potenciador", "de": "Verstärker", "it": "Potenziatore", "pt": "Amplificador", "ru": "Усилитель", "ja": "ブースター", "zh": "增幅器", "ar": "معزز"},
	"module.6.name": {"en": "Mine", "fr": "Mine", "es": "Mina", "de": "Mine", "it": "Mina", "pt": "Mina", "ru": "Мина", "ja": "地雷", "zh": "地雷", "ar": "لغم"},
	"module.7.name": {"en": "Emergency shield", "fr": "Bouclier d'urgence", "es": "Escudo de emergencia", "de": "Notschild", "it": "Scudo d'emergenza", "pt": "Escudo de emergência", "ru": "Аварийный щит", "ja": "緊急シールド", "zh": "紧急护盾", "ar": "درع طوارئ"},
	"module.8.name": {"en": "EMP bomb", "fr": "Bombe EMP", "es": "Bomba EMP", "de": "EMP-Bombe", "it": "Bomba EMP", "pt": "Bomba EMP", "ru": "ЭМИ-бомба", "ja": "EMP爆弾", "zh": "电磁脉冲炸弹", "ar": "قنبلة EMP"},
	"module.tooltip_level": {"en": " (lvl. %d)", "fr": " (niv. %d)", "es": " (niv. %d)", "de": " (Stufe %d)", "it": " (liv. %d)", "pt": " (nív. %d)", "ru": " (ур. %d)", "ja": "（Lv.%d）", "zh": "（等级 %d）", "ar": " (المستوى %d)"},
	"module.tooltip_disabled": {"en": " · 🔒 disabled (Saboteur)", "fr": " · 🔒 désactivé (Saboteur)", "es": " · 🔒 desactivado (Saboteador)", "de": " · 🔒 deaktiviert (Saboteur)", "it": " · 🔒 disattivato (Sabotatore)", "pt": " · 🔒 desativado (Sabotador)", "ru": " · 🔒 отключено (Саботажник)", "ja": " · 🔒 無効（サボタージュ）", "zh": " · 🔒 已失效（破坏者）", "ar": " · 🔒 معطّل (المخرب)"},
	"outpost.label": {"en": "Outpost %d", "fr": "Avant-poste %d", "es": "Avanzada %d", "de": "Außenposten %d", "it": "Avamposto %d", "pt": "Posto avançado %d", "ru": "Форпост %d", "ja": "前哨基地 %d", "zh": "前哨站 %d", "ar": "المخفر %d"},
	"upgrade.hint": {"en": "Click a station slot to build or upgrade", "fr": "Clique sur un emplacement de la station pour construire ou améliorer", "es": "Haz clic en un hueco de la estación para construir o mejorar", "de": "Klicke auf einen Stationsplatz zum Bauen oder Verbessern", "it": "Clicca su uno slot della stazione per costruire o potenziare", "pt": "Clica numa ranhura da estação para construir ou melhorar", "ru": "Нажмите на слот станции, чтобы построить или улучшить", "ja": "ステーションのスロットをクリックして建設・強化", "zh": "点击空间站的插槽进行建造或升级", "ar": "انقر على خانة في المحطة للبناء أو الترقية"},
	"module.9.name": {"en": "Drill", "fr": "Foreuse", "es": "Perforadora", "de": "Bohrer", "it": "Trivella", "pt": "Perfuradora", "ru": "Бур", "ja": "ドリル", "zh": "钻机", "ar": "حفارة"},
}
