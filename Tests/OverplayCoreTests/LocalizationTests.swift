import XCTest
@testable import OverplayCore

final class LocalizationTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("overplay-localization-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeStore() -> LocalizationStore {
        LocalizationStore(
            packsDirectory: directory,
            builtinCatalogs: [
                "zh-Hans": [
                    "common.cancel": "取消",
                    "common.save": "保存",
                    "greeting": "你好",
                    "greeting.name": "你好 {0}",
                    "count": "共 {0} 个",
                    "demo.disclaimer": "演示模式中的厂商数据、用量、费用、余额、额度、进度与告警均为模拟数据，仅用于展示产品功能。"
                ],
                "zh-Hant": [
                    "common.cancel": "取消",
                    "common.save": "儲存",
                    "greeting": "你好"
                ],
                "en": [
                    "common.cancel": "Cancel",
                    "common.save": "Save",
                    "greeting": "Hello",
                    "greeting.name": "Hello {0}",
                    "count": "{0} items"
                ]
            ]
        )
    }

    func testSystemLanguageResolution() {
        XCTAssertEqual(AppLanguage.resolveSystem(preferred: ["zh-Hant-TW"]), .traditionalChinese)
        XCTAssertEqual(AppLanguage.resolveSystem(preferred: ["zh-HK"]), .traditionalChinese)
        XCTAssertEqual(AppLanguage.resolveSystem(preferred: ["zh-Hans-CN"]), .simplifiedChinese)
        XCTAssertEqual(AppLanguage.resolveSystem(preferred: ["en-US"]), .english)
        XCTAssertEqual(AppLanguage.resolveSystem(preferred: ["fr-FR"]), .simplifiedChinese)
    }

    func testBuiltinFallbackAndFormatting() {
        let store = makeStore()
        store.setLanguage(.english)
        XCTAssertEqual(store.tr("common.cancel"), "Cancel")
        XCTAssertEqual(store.tr("greeting.name"), "Hello {0}")
        XCTAssertEqual(store.format("greeting.name", "Ada"), "Hello Ada")
        XCTAssertEqual(store.format("count", 3), "3 items")
        // Missing English key falls back to zh-Hans.
        XCTAssertEqual(store.tr("common.save"), "Save")
        store.setLanguage(.traditionalChinese)
        XCTAssertEqual(store.tr("common.cancel"), "取消")
        XCTAssertEqual(store.tr("common.save"), "儲存")
    }

    func testRawSourceStringAndDynamicPatternTranslation() {
        let store = makeStore()
        store.setLanguage(.english)
        XCTAssertEqual(store.tr("你好"), "Hello")
        XCTAssertEqual(store.tr("你好 Ada"), "Hello Ada")
        XCTAssertEqual(store.tr("共 12 个"), "12 items")
        store.setLanguage(.simplifiedChinese)
        XCTAssertEqual(store.tr("你好 Ada"), "你好 Ada")
    }

    func testValidPackImportSelectAndRemove() throws {
        let store = makeStore()
        let data = try makePackJSON(
            locale: "ja",
            fallback: "zh-Hans",
            strings: ["common.cancel": "キャンセル", "greeting.name": "こんにちは {0}"]
        )
        let pack = try store.importPack(data: data, appVersion: "1.0")
        XCTAssertEqual(pack.locale, "ja")
        try store.setImportedLanguage(locale: "ja")
        XCTAssertEqual(store.tr("common.cancel"), "キャンセル")
        XCTAssertEqual(store.format("greeting.name", "Ada"), "こんにちは Ada")
        // Missing key falls back to zh-Hans.
        XCTAssertEqual(store.tr("common.save"), "保存")
        XCTAssertEqual(store.importedPacks.count, 1)
        try store.removePack(locale: "ja")
        XCTAssertTrue(store.importedPacks.isEmpty)
        XCTAssertEqual(store.effectiveLocale, AppLanguage.resolveSystem().builtinLocale ?? "zh-Hans")
    }

    func testPackPersistsAcrossStoreInstances() throws {
        let first = makeStore()
        let data = try makePackJSON(
            locale: "ja",
            fallback: "zh-Hans",
            strings: ["common.cancel": "キャンセル"]
        )
        _ = try first.importPack(data: data, appVersion: "1.0")
        let second = makeStore()
        XCTAssertEqual(second.importedPacks.map(\.locale), ["ja"])
        try second.setImportedLanguage(locale: "ja")
        XCTAssertEqual(second.tr("common.cancel"), "キャンセル")
    }

    func testPackSourceKeyAndChainedFallback() throws {
        let store = makeStore()
        let japanese = try store.importPack(
            data: try makePackJSON(
                locale: "ja",
                fallback: "zh-Hans",
                strings: ["取消": "キャンセル"]
            ),
            appVersion: "1.0"
        )
        XCTAssertEqual(japanese.strings["取消"], "キャンセル")
        try store.setImportedLanguage(locale: "ja")
        XCTAssertEqual(store.tr("common.cancel"), "キャンセル")

        let korean = try store.importPack(
            data: try makePackJSON(
                locale: "ko",
                fallback: "ja",
                strings: ["common.save": "저장"]
            ),
            appVersion: "1.0"
        )
        XCTAssertEqual(korean.fallbackLocale, "ja")
        try store.setImportedLanguage(locale: "ko")
        XCTAssertEqual(store.tr("common.save"), "저장")
        XCTAssertEqual(store.tr("common.cancel"), "キャンセル")
    }

    func testPackValidationFailures() throws {
        XCTAssertThrowsError(try makeStore().importPack(
            data: Data("{}".utf8),
            appVersion: "1.0"
        )) { error in
            XCTAssertEqual(error as? LanguagePackError, .missingField("formatVersion"))
        }

        let badVersion = try makePackJSON(
            locale: "ja",
            fallback: "zh-Hans",
            strings: ["common.cancel": "キャンセル"],
            formatVersion: 2
        )
        XCTAssertThrowsError(try makeStore().importPack(data: badVersion, appVersion: "1.0")) { error in
            XCTAssertEqual(error as? LanguagePackError, .unsupportedFormatVersion(2))
        }

        let builtin = try makePackJSON(
            locale: "zh-Hans",
            fallback: "en",
            strings: ["common.cancel": "取消"]
        )
        XCTAssertThrowsError(try makeStore().importPack(data: builtin, appVersion: "1.0")) { error in
            XCTAssertEqual(error as? LanguagePackError, .builtinLocale("zh-Hans"))
        }

        let invalidLocale = try makePackJSON(
            locale: "ja_JP!",
            fallback: "zh-Hans",
            strings: ["common.cancel": "キャンセル"]
        )
        XCTAssertThrowsError(try makeStore().importPack(data: invalidLocale, appVersion: "1.0")) { error in
            XCTAssertEqual(error as? LanguagePackError, .invalidLocale("ja_JP!"))
        }

        let badRange = try makePackJSON(
            locale: "ja",
            fallback: "zh-Hans",
            versionRange: "not-a-range",
            strings: ["common.cancel": "キャンセル"]
        )
        XCTAssertThrowsError(try makeStore().importPack(data: badRange, appVersion: "1.0")) { error in
            XCTAssertEqual(error as? LanguagePackError, .versionRangeInvalid("not-a-range"))
        }

        let incompatible = try makePackJSON(
            locale: "ja",
            fallback: "zh-Hans",
            versionRange: ">=2.0 <3.0",
            strings: ["common.cancel": "キャンセル"]
        )
        XCTAssertThrowsError(try makeStore().importPack(data: incompatible, appVersion: "1.0")) { error in
            XCTAssertEqual(error as? LanguagePackError, .appVersionIncompatible(">=2.0 <3.0"))
        }
    }

    func testPackRejectsNestedScriptUnsafeAndDuplicateContent() throws {
        let nested = try makeJSON([
            "formatVersion": 1,
            "locale": "ja",
            "displayName": "日本語",
            "fallbackLocale": "zh-Hans",
            "appVersionRange": ">=1.0 <2.0",
            "strings": ["common.cancel": ["nested": "x"]]
        ])
        XCTAssertThrowsError(try makeStore().importPack(data: nested, appVersion: "1.0")) { error in
            XCTAssertEqual(error as? LanguagePackError, .nestedValue("common.cancel"))
        }

        let script = try makePackJSON(
            locale: "ja",
            fallback: "zh-Hans",
            strings: ["common.cancel": "<script>alert(1)</script>"]
        )
        XCTAssertThrowsError(try makeStore().importPack(data: script, appVersion: "1.0")) { error in
            guard case .unsafeContent = error as? LanguagePackError else {
                return XCTFail("unexpected \(error)")
            }
        }

        let traversal = try makePackJSON(
            locale: "ja",
            fallback: "zh-Hans",
            strings: ["../common.cancel": "キャンセル"]
        )
        XCTAssertThrowsError(try makeStore().importPack(data: traversal, appVersion: "1.0")) { error in
            guard case .unsafeContent = error as? LanguagePackError else {
                return XCTFail("unexpected \(error)")
            }
        }

        let duplicate = Data("""
        {
          "formatVersion": 1,
          "locale": "ja",
          "displayName": "日本語",
          "fallbackLocale": "zh-Hans",
          "appVersionRange": ">=1.0 <2.0",
          "strings": {
            "common.cancel": "A",
            "common.cancel": "B"
          }
        }
        """.utf8)
        XCTAssertThrowsError(try makeStore().importPack(data: duplicate, appVersion: "1.0")) { error in
            XCTAssertEqual(error as? LanguagePackError, .duplicateKey("common.cancel"))
        }

        let placeholder = try makePackJSON(
            locale: "ja",
            fallback: "zh-Hans",
            strings: ["greeting.name": "こんにちは"]
        )
        XCTAssertThrowsError(try makeStore().importPack(data: placeholder, appVersion: "1.0")) { error in
            XCTAssertEqual(error as? LanguagePackError, .placeholderMismatch("greeting.name"))
        }

        let empty = try makePackJSON(
            locale: "ja",
            fallback: "zh-Hans",
            strings: ["common.cancel": ""]
        )
        XCTAssertThrowsError(try makeStore().importPack(data: empty, appVersion: "1.0")) { error in
            XCTAssertEqual(error as? LanguagePackError, .invalidField("strings[common.cancel]"))
        }

        let shortDisclaimer = try makePackJSON(
            locale: "ja",
            fallback: "zh-Hans",
            strings: ["demo.disclaimer": "short"]
        )
        XCTAssertThrowsError(try makeStore().importPack(data: shortDisclaimer, appVersion: "1.0")) { error in
            XCTAssertEqual(error as? LanguagePackError, .invalidField("demo.disclaimer"))
        }
    }

    func testPackFallbackCycleAndOversize() throws {
        let store = makeStore()
        _ = try store.importPack(
            data: try makePackJSON(
                locale: "ja",
                fallback: "zh-Hans",
                strings: ["common.cancel": "キャンセル"]
            ),
            appVersion: "1.0"
        )
        let cyclic = try makePackJSON(
            locale: "ko",
            fallback: "ko",
            strings: ["common.cancel": "취소"]
        )
        XCTAssertThrowsError(try store.importPack(data: cyclic, appVersion: "1.0")) { error in
            XCTAssertEqual(error as? LanguagePackError, .fallbackCycle("ko"))
        }

        let oversized = Data(repeating: 0x20, count: LocalizedLanguagePack.maxFileSize + 1)
        XCTAssertThrowsError(try store.importPack(data: oversized, appVersion: "1.0")) { error in
            XCTAssertEqual(error as? LanguagePackError, .fileTooLarge)
        }
    }

    func testSemanticVersionRange() throws {
        let range = try XCTUnwrap(SemanticVersionRange(">=1.0 <2.0"))
        XCTAssertTrue(range.contains(try XCTUnwrap(SemanticVersion("1.0"))))
        XCTAssertTrue(range.contains(try XCTUnwrap(SemanticVersion("1.9.9"))))
        XCTAssertFalse(range.contains(try XCTUnwrap(SemanticVersion("2.0"))))
        XCTAssertFalse(range.contains(try XCTUnwrap(SemanticVersion("0.9"))))

        let spaced = try XCTUnwrap(SemanticVersionRange(">= 1.0 < 2.0"))
        XCTAssertTrue(spaced.contains(try XCTUnwrap(SemanticVersion("1.2"))))

        let exclusive = try XCTUnwrap(SemanticVersionRange(">1.0 <=2.0"))
        XCTAssertFalse(exclusive.contains(try XCTUnwrap(SemanticVersion("1.0"))))
        XCTAssertTrue(exclusive.contains(try XCTUnwrap(SemanticVersion("2.0"))))
    }

    func testAvailableLanguagesIncludesSystemBuiltinAndImported() throws {
        let store = makeStore()
        _ = try store.importPack(
            data: try makePackJSON(
                locale: "ja",
                fallback: "zh-Hans",
                strings: ["common.cancel": "キャンセル"]
            ),
            appVersion: "1.0"
        )
        let languages = store.availableLanguages
        XCTAssertEqual(languages.prefix(4).map(\.id), ["system", "zh-Hans", "zh-Hant", "en"])
        XCTAssertTrue(languages.contains { $0.id == "ja" && $0.isImported })
    }

    func testBuiltInCatalogsAreCompleteAndEnglishIsTranslated() {
        let store = LocalizationStore(packsDirectory: directory)
        let keys = store.builtinLocaleKeys()
        let zh = store.builtinCatalog(for: "zh-Hans")
        let hant = store.builtinCatalog(for: "zh-Hant")
        let en = store.builtinCatalog(for: "en")
        XCTAssertGreaterThan(keys.count, 800)
        XCTAssertEqual(Set(zh.keys), keys)
        XCTAssertEqual(Set(hant.keys), keys)
        XCTAssertEqual(Set(en.keys), keys)
        for (key, value) in en {
            XCTAssertFalse(value.isEmpty, "Empty English translation for \(key)")
            if value.range(of: "[\\u4e00-\\u9fff]", options: .regularExpression) != nil {
                XCTAssertTrue(
                    key == "language.zhHans" || key == "language.zhHant",
                    "English catalog contains Chinese text for \(key): \(value)"
                )
            }
        }
        XCTAssertNotEqual(hant["settings.language.title"], zh["settings.language.title"])
    }

    func testRealCatalogTranslationAndDynamicPattern() {
        let store = LocalizationStore(packsDirectory: directory)
        store.setLanguage(.english)
        XCTAssertEqual(store.tr("settings.language.title"), "Language")
        XCTAssertEqual(store.tr("settings.a69e4d32ff"), "Refresh & Notifications")
        XCTAssertEqual(store.format("settings.eb7fa47f34", 15), "Every 15 minutes")
        XCTAssertEqual(store.tr("已添加 Demo，开始监控"), "Added Demo; monitoring started")
        XCTAssertEqual(store.tr("已添加 Demo，开始监控"), "Added Demo; monitoring started")
        store.setLanguage(.traditionalChinese)
        XCTAssertEqual(store.tr("settings.language.title"), "語言")
        XCTAssertNotEqual(store.tr("settings.a69e4d32ff"), "Refresh & Notifications")
    }

    func testImportedPackOverridesRealKeyAndFallsBack() throws {
        let store = LocalizationStore(packsDirectory: directory)
        let pack = try store.importPack(
            data: try makePackJSON(
                locale: "ja",
                fallback: "zh-Hans",
                strings: ["settings.language.title": "言語"]
            ),
            appVersion: "1.0"
        )
        XCTAssertEqual(pack.displayName, "Test ja")
        try store.setImportedLanguage(locale: "ja")
        XCTAssertEqual(store.tr("settings.language.title"), "言語")
        // Missing keys fall back to zh-Hans, never to a raw key.
        XCTAssertEqual(store.tr("settings.a69e4d32ff"), "刷新与通知")
    }

    func testAllWrappedSourceKeysExistInCatalog() throws {
        let store = LocalizationStore(packsDirectory: directory)
        let keys = store.builtinLocaleKeys()
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sources = root.appendingPathComponent("Sources", isDirectory: true)
        let pattern = try NSRegularExpression(pattern: "L10n\\.(?:t|f)\\(\"([^\"]+)\"")
        var missing: Set<String> = []
        var scanned = 0
        let files = FileManager.default.enumerator(
            at: sources,
            includingPropertiesForKeys: nil
        )?.compactMap { $0 as? URL } ?? []
        for file in files where file.pathExtension == "swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            scanned += 1
            let range = NSRange(text.startIndex..., in: text)
            for match in pattern.matches(in: text, range: range) {
                if let keyRange = Range(match.range(at: 1), in: text) {
                    let key = String(text[keyRange])
                    // Interpolated keys are validated by their concrete catalog
                    // consumers and dedicated tests, not by a static lookup.
                    guard !key.contains("\\("), !key.contains("{") else { continue }
                    if !keys.contains(key) { missing.insert(key) }
                }
            }
        }
        XCTAssertGreaterThan(scanned, 20)
        XCTAssertTrue(missing.isEmpty, "Missing localization keys: \(missing.sorted())")
    }

    func testClearPacksResetsSelection() throws {
        let store = makeStore()
        for locale in ["ja", "ko"] {
            _ = try store.importPack(
                data: try makePackJSON(
                    locale: locale,
                    fallback: "zh-Hans",
                    strings: ["common.cancel": locale == "ja" ? "キャンセル" : "취소"]
                ),
                appVersion: "1.0"
            )
        }
        try store.setImportedLanguage(locale: "ja")
        try store.clearPacks()
        XCTAssertTrue(store.importedPacks.isEmpty)
        XCTAssertFalse(store.isUsingImportedPack)
        XCTAssertEqual(store.effectiveLocale, AppLanguage.resolveSystem().builtinLocale ?? "zh-Hans")
    }

    func testRepresentativeErrorsAreLocalized() {
        let previous = LocalizationStore.shared.language
        defer { LocalizationStore.shared.setLanguage(previous) }
        LocalizationStore.shared.setLanguage(.english)

        XCTAssertEqual(
            AccountValidationError.emptyCredential.errorDescription,
            "API Key / Management Key cannot be empty"
        )
        XCTAssertEqual(
            GenericHTTPConfigError.requiresHTTPS.errorDescription,
            "Generic HTTP accepts HTTPS endpoints only"
        )
        XCTAssertEqual(
            LanguagePackError.fileTooLarge.errorDescription,
            "Language pack exceeds the 1 MB limit"
        )
        XCTAssertEqual(
            LanguagePackError.malformedJSON("根节点必须是对象").errorDescription,
            "Malformed language pack JSON: root must be an object"
        )
        XCTAssertEqual(
            LanguagePackError.unsafeContent("脚本内容").errorDescription,
            "Language pack contains unsafe content: script content"
        )
        for error in [
            AccountValidationError.emptyCredential,
            AccountValidationError.duplicateName,
            AccountValidationError.missingGenericConfig,
            AccountValidationError.missingMapping
        ] {
            let text = error.errorDescription ?? ""
            XCTAssertNil(
                text.range(of: "[\\u4e00-\\u9fff]", options: .regularExpression),
                "English error still contains Chinese: \(text)"
            )
        }
        for error in [
            GenericHTTPConfigError.invalidURL,
            GenericHTTPConfigError.requiresHTTPS,
            GenericHTTPConfigError.embeddedCredentials,
            GenericHTTPConfigError.privateAddress,
            GenericHTTPConfigError.metadataAddress,
            GenericHTTPConfigError.localhost
        ] {
            let text = error.errorDescription ?? ""
            XCTAssertNil(
                text.range(of: "[\\u4e00-\\u9fff]", options: .regularExpression),
                "English error still contains Chinese: \(text)"
            )
        }

        LocalizationStore.shared.setLanguage(.traditionalChinese)
        XCTAssertEqual(
            AccountValidationError.emptyCredential.errorDescription,
            "API Key / Management Key 不能為空"
        )
    }

    func testAlertEventsUseTemplateKeyAndParamsForTextValues() {
        let previous = LocalizationStore.shared.language
        defer { LocalizationStore.shared.setLanguage(previous) }
        LocalizationStore.shared.setLanguage(.english)

        let now = TestClock.date(2026, 10, 31, 12)
        let sync = AlertEvent(
            accountId: "a",
            accountName: "Account A",
            kind: .syncFailed,
            firedAt: now,
            value: "连续 3 次",
            threshold: "3 次",
            metric: "同步失败告警（6 小时冷却）",
            periodKey: "cooldown"
        )
        XCTAssertEqual(sync.templateKey, "alert.syncFailed")
        XCTAssertEqual(sync.renderedTitle, "Consecutive sync failures")
        XCTAssertEqual(sync.renderedValue, "3 consecutive failures")
        XCTAssertEqual(sync.renderedThreshold, "3 times")

        let credential = AlertEvent(
            accountId: "a",
            accountName: "Account A",
            kind: .credentialInvalid,
            firedAt: now,
            value: "401 / 403",
            threshold: "凭据需重新输入",
            metric: "凭据失效，已暂停自动重试",
            periodKey: "credential"
        )
        XCTAssertEqual(credential.renderedThreshold, "Credential must be re-entered")

        let stale = AlertEvent(
            accountId: "a",
            accountName: "Account A",
            kind: .dataStale,
            firedAt: now,
            value: "从未成功同步",
            threshold: "120 分钟",
            metric: "超过 2 个刷新周期未成功同步",
            periodKey: "stale"
        )
        XCTAssertEqual(stale.renderedValue, "Never synced successfully")
        XCTAssertEqual(stale.renderedThreshold, "120 minutes")

        LocalizationStore.shared.setLanguage(.traditionalChinese)
        XCTAssertEqual(sync.renderedValue, "連續 3 次")
        XCTAssertEqual(stale.renderedThreshold, "120 分鐘")
    }

    func testAlertMetricLocalizationSplitsLineMetric() {
        let previous = LocalizationStore.shared.language
        defer { LocalizationStore.shared.setLanguage(previous) }
        LocalizationStore.shared.setLanguage(.english)
        XCTAssertEqual(AlertKind.budgetExceeded.title, "Budget exhausted")
        XCTAssertEqual(
            AlertMetricText.localized("预算 % · 公共告知线"),
            "Budget % · Public notice line"
        )
        XCTAssertEqual(
            AlertMetricText.localized("本地预算月度使用率（$100.00 / 月）"),
            "Local monthly budget usage ($100.00 / month)"
        )
    }

    func testMoneyAndDateFollowSelectedLanguage() {
        let previous = LocalizationStore.shared.language
        defer { LocalizationStore.shared.setLanguage(previous) }
        LocalizationStore.shared.setLanguage(.english)
        XCTAssertEqual(Money.format(1234.56, currency: "USD", minimumFractionDigits: 2, maximumFractionDigits: 2), "$1,234.56")
        let date = Date(timeIntervalSince1970: 1_774_400_000)
        let english = DateFormatters.mediumDateTime.string(from: date)
        XCTAssertTrue(english.contains("2026") || english.contains("2025"))
        XCTAssertFalse(english.contains("年"))
        LocalizationStore.shared.setLanguage(.simplifiedChinese)
        let chinese = DateFormatters.mediumDateTime.string(from: date)
        XCTAssertTrue(chinese.contains("-"))
    }

    func testPackCanFallBackToBuiltInEnglish() throws {
        let store = makeStore()
        _ = try store.importPack(
            data: try makePackJSON(
                locale: "ja",
                fallback: "en",
                strings: ["common.cancel": "キャンセル"]
            ),
            appVersion: "1.0"
        )
        try store.setImportedLanguage(locale: "ja")
        XCTAssertEqual(store.tr("common.cancel"), "キャンセル")
        XCTAssertEqual(store.tr("common.save"), "Save")
    }

    func testSampleLanguagePackImports() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = root.appendingPathComponent("docs/examples/language-pack-ja.json")
        let store = LocalizationStore(packsDirectory: directory)
        let pack = try store.importPack(
            data: try Data(contentsOf: url),
            appVersion: "1.0"
        )
        XCTAssertEqual(pack.locale, "ja")
        try store.setImportedLanguage(locale: "ja")
        XCTAssertEqual(store.tr("common.cancel"), "キャンセル")
        XCTAssertEqual(store.tr("settings.a69e4d32ff"), "更新と通知")
    }

    func testAppTargetHasNoHardcodedChineseStrings() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appSources = root.appendingPathComponent("Sources/OverplayApp", isDirectory: true)
        let files = FileManager.default.enumerator(
            at: appSources,
            includingPropertiesForKeys: nil
        )?.compactMap { $0 as? URL } ?? []
        let chinese = try NSRegularExpression(pattern: "\"[^\"\\n\\\\]*(?:\\\\.[^\"\\n\\\\]*)*[\\u4e00-\\u9fff]")
        var offenders: [String] = []
        for file in files where file.pathExtension == "swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            let range = NSRange(text.startIndex..., in: text)
            if chinese.firstMatch(in: text, range: range) != nil {
                offenders.append(file.lastPathComponent)
            }
        }
        XCTAssertTrue(offenders.isEmpty, "Hardcoded Chinese remains in app sources: \(offenders)")
    }

    // MARK: - Helpers

    private func makePackJSON(
        locale: String,
        fallback: String,
        versionRange: String = ">=1.0 <2.0",
        strings: [String: String],
        formatVersion: Int = 1
    ) throws -> Data {
        try makeJSON([
            "formatVersion": formatVersion,
            "locale": locale,
            "displayName": "Test \(locale)",
            "fallbackLocale": fallback,
            "appVersionRange": versionRange,
            "strings": strings
        ])
    }

    private func makeJSON(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}
