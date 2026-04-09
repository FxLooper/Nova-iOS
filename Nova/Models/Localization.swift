import Foundation

struct L10n {
    static var current: String {
        UserDefaults.standard.string(forKey: "nova_lang") ?? "cs"
    }

    static let strings: [String: [String: String]] = [
        "cs": [
            "settings": "Nastavení", "save": "Uložit", "name": "Jméno",
            "name_placeholder": "Tvoje jméno", "city": "Domovské město",
            "city_placeholder": "Město", "language": "Jazyk",
            "voice": "Hlas asistenta", "female": "Ženský", "male": "Mužský",
            "connection": "Připojení", "connected": "Připojeno", "disconnected": "Odpojeno",
            "change_server": "Změnit server", "ready": "Připravena",
            "listening": "Poslouchám...", "thinking": "Přemýšlím...", "speaking": "Mluvím...",
            "write_nova": "Napiš Nově...", "you": "Ty",
            "connect": "Připojit", "server_title": "Připojení k serveru",
        ],
        "en": [
            "settings": "Settings", "save": "Save", "name": "Name",
            "name_placeholder": "Your name", "city": "Home city",
            "city_placeholder": "City", "language": "Language",
            "voice": "Assistant voice", "female": "Female", "male": "Male",
            "connection": "Connection", "connected": "Connected", "disconnected": "Disconnected",
            "change_server": "Change server", "ready": "Ready",
            "listening": "Listening...", "thinking": "Thinking...", "speaking": "Speaking...",
            "write_nova": "Write to Nova...", "you": "You",
            "connect": "Connect", "server_title": "Connect to server",
        ],
        "de": [
            "settings": "Einstellungen", "save": "Speichern", "name": "Name",
            "name_placeholder": "Dein Name", "city": "Heimatstadt",
            "city_placeholder": "Stadt", "language": "Sprache",
            "voice": "Assistentenstimme", "female": "Weiblich", "male": "Männlich",
            "connection": "Verbindung", "connected": "Verbunden", "disconnected": "Getrennt",
            "change_server": "Server ändern", "ready": "Bereit",
            "listening": "Höre zu...", "thinking": "Denke nach...", "speaking": "Spreche...",
            "write_nova": "Schreib Nova...", "you": "Du",
            "connect": "Verbinden", "server_title": "Mit Server verbinden",
        ],
        "fr": [
            "settings": "Paramètres", "save": "Enregistrer", "name": "Nom",
            "name_placeholder": "Ton nom", "city": "Ville",
            "city_placeholder": "Ville", "language": "Langue",
            "voice": "Voix de l'assistant", "female": "Féminine", "male": "Masculine",
            "connection": "Connexion", "connected": "Connecté", "disconnected": "Déconnecté",
            "change_server": "Changer de serveur", "ready": "Prête",
            "listening": "J'écoute...", "thinking": "Je réfléchis...", "speaking": "Je parle...",
            "write_nova": "Écris à Nova...", "you": "Toi",
            "connect": "Connecter", "server_title": "Connexion au serveur",
        ],
        "es": [
            "settings": "Ajustes", "save": "Guardar", "name": "Nombre",
            "name_placeholder": "Tu nombre", "city": "Ciudad",
            "city_placeholder": "Ciudad", "language": "Idioma",
            "voice": "Voz del asistente", "female": "Femenina", "male": "Masculina",
            "connection": "Conexión", "connected": "Conectado", "disconnected": "Desconectado",
            "change_server": "Cambiar servidor", "ready": "Lista",
            "listening": "Escuchando...", "thinking": "Pensando...", "speaking": "Hablando...",
            "write_nova": "Escribe a Nova...", "you": "Tú",
            "connect": "Conectar", "server_title": "Conexión al servidor",
        ],
        "ja": [
            "settings": "設定", "save": "保存", "name": "名前",
            "name_placeholder": "あなたの名前", "city": "ホームシティ",
            "city_placeholder": "都市", "language": "言語",
            "voice": "アシスタントの声", "female": "女性", "male": "男性",
            "connection": "接続", "connected": "接続済み", "disconnected": "未接続",
            "change_server": "サーバー変更", "ready": "準備完了",
            "listening": "聞いています...", "thinking": "考えています...", "speaking": "話しています...",
            "write_nova": "Novaに書く...", "you": "あなた",
            "connect": "接続", "server_title": "サーバーに接続",
        ],
        "zh": [
            "settings": "设置", "save": "保存", "name": "姓名",
            "name_placeholder": "你的名字", "city": "所在城市",
            "city_placeholder": "城市", "language": "语言",
            "voice": "助手语音", "female": "女声", "male": "男声",
            "connection": "连接", "connected": "已连接", "disconnected": "未连接",
            "change_server": "更改服务器", "ready": "就绪",
            "listening": "聆听中...", "thinking": "思考中...", "speaking": "说话中...",
            "write_nova": "写给Nova...", "you": "你",
            "connect": "连接", "server_title": "连接到服务器",
        ],
    ]

    static func t(_ key: String) -> String {
        strings[current]?[key] ?? strings["en"]?[key] ?? key
    }
}
