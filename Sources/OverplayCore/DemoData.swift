import Foundation

public enum DemoMode {
    public static var disclaimer: String {
        L10n.t("demo.disclaimer")
    }

    public static var shortBadge: String {
        L10n.t("demo.shortBadge")
    }
}

private struct DemoUsageModel {
    var name: String
    var vendor: String
    var prompt: Int
    var completion: Int
    var reasoning: Int
    var cost: Decimal
}

private struct DemoPlatformSpec {
    var id: String
    var provider: ProviderKind
    var name: String
    var ageDays: Int
    var currency: String
    var totalCredits: Decimal
    var totalUsage: Decimal
    var budget: Decimal?
    var models: [DemoUsageModel]
}

public enum DemoData {
    public static func makeStore(now: Date = Date()) throws -> OverplayStore {
        let store = try OverplayStore.inMemory()
        let demoDeepSeek = Account(
            id: "demo-deepseek",
            provider: .deepseek,
            name: "DeepSeek 演示账户",
            enabled: true,
            createdAt: now.addingTimeInterval(-42 * 86_400),
            lastSuccessAt: now.addingTimeInterval(-120),
            lastAttemptAt: now.addingTimeInterval(-120),
            balanceThreshold: BalanceThreshold(amount: 100, currency: "CNY"),
            isDemo: true,
            officialName: "DeepSeek 官方余额演示"
        )
        let demoDeepSeekUSD = Account(
            id: "demo-deepseek-usd",
            provider: .deepseek,
            name: "DeepSeek 演示账户（USD）",
            enabled: true,
            createdAt: now.addingTimeInterval(-41 * 86_400),
            lastSuccessAt: now.addingTimeInterval(-240),
            lastAttemptAt: now.addingTimeInterval(-240),
            balanceThreshold: BalanceThreshold(amount: 20, currency: "USD"),
            isDemo: true
        )
        let demoOpenRouter = Account(
            id: "demo-openrouter",
            provider: .openrouter,
            name: "OpenRouter 演示账户",
            enabled: true,
            createdAt: now.addingTimeInterval(-40 * 86_400),
            lastSuccessAt: now.addingTimeInterval(-300),
            lastAttemptAt: now.addingTimeInterval(-300),
            budget: Budget(amount: 100, currency: "USD"),
            isDemo: true,
            officialName: "OpenRouter activity 演示组织"
        )
        try store.insertAccount(demoDeepSeek)
        try store.insertAccount(demoDeepSeekUSD)
        try store.insertAccount(demoOpenRouter)

        let balanceValues: [Decimal] = [238.40, 212.10, 187.55, 161.20, 138.90, 116.30, 92.40]
        for (index, value) in balanceValues.enumerated() {
            let offset = -120 - Double(balanceValues.count - 1 - index) * 4 * 86_400
            let asOf = now.addingTimeInterval(offset)
            try store.insertBalanceSnapshots([BalanceSnapshot(
                id: "demo-balance-\(index)",
                accountId: demoDeepSeek.id,
                currency: "CNY",
                total: value,
                granted: 10,
                toppedUp: value - 10,
                isAvailable: true,
                asOf: asOf,
                source: "演示数据 · DeepSeek 官方余额模型"
            )])
        }

        let usdBalanceValues: [Decimal] = [64.80, 58.30, 51.90, 47.20, 41.50, 37.10, 32.60]
        for (index, value) in usdBalanceValues.enumerated() {
            let offset = -240 - Double(usdBalanceValues.count - 1 - index) * 4 * 86_400
            let asOf = now.addingTimeInterval(offset)
            try store.insertBalanceSnapshots([BalanceSnapshot(
                id: "demo-balance-usd-\(index)",
                accountId: demoDeepSeekUSD.id,
                currency: "USD",
                total: value,
                granted: 5,
                toppedUp: value - 5,
                isAvailable: true,
                asOf: asOf,
                source: "演示数据 · DeepSeek 官方余额模型（USD）"
            )])
        }

        try store.insertQuotaSnapshot(QuotaSnapshot(
            id: "demo-quota",
            accountId: demoOpenRouter.id,
            totalCredits: 500,
            totalUsage: 425.60,
            remaining: 74.40,
            currency: "USD",
            asOf: now.addingTimeInterval(-300),
            source: "演示数据 · OpenRouter credits 模型"
        ))

        let models: [(name: String, prompt: Int, completion: Int, reasoning: Int, cost: Decimal)] = [
            ("anthropic/claude-sonnet-4.5", 24_000, 6_500, 900, Decimal(string: "2.2")!),
            ("openai/gpt-5.2", 18_000, 4_200, 300, Decimal(string: "1.6")!),
            ("deepseek/deepseek-v3.2", 32_000, 8_100, 1_200, Decimal(string: "1.0")!)
        ]
        var usage: [UsageRecord] = []
        for (dayIndex, day) in lastCompleteUTCDays(now: now).enumerated() {
            let factor = 0.8 + Decimal(dayIndex % 5) * 0.1
            for (modelIndex, model) in models.enumerated() {
                let requests = 40 + dayIndex * 3 + modelIndex * 17
                usage.append(UsageRecord(
                    id: "demo-\(day)-\(modelIndex)",
                    accountId: demoOpenRouter.id,
                    accountName: demoOpenRouter.displayName,
                    provider: .openrouter,
                    day: day,
                    model: model.name,
                    providerName: modelIndex == 0 ? "Anthropic" : modelIndex == 1 ? "OpenAI" : "DeepSeek",
                    promptTokens: NSDecimalNumber(decimal: Decimal(model.prompt) * factor).intValue,
                    completionTokens: NSDecimalNumber(decimal: Decimal(model.completion) * factor).intValue,
                    reasoningTokens: NSDecimalNumber(decimal: Decimal(model.reasoning) * factor).intValue,
                    cachedTokens: modelIndex == 0 ? 4_000 : nil,
                    requests: requests,
                    cost: Money.rounded(model.cost * factor, scale: 2),
                    byokCost: dayIndex % 4 == 0 && modelIndex == 1 ? Decimal(string: "0.12")! : nil,
                    currency: "USD",
                    source: "演示数据 · OpenRouter activity 模型（UTC 日桶）",
                    updatedAt: now.addingTimeInterval(-300)
                ))
            }
        }

        try store.upsertUsage(usage, accountName: demoOpenRouter.displayName)

        try insertPlatformDemoData(store: store, now: now)

        let monthSpend = try store.monthSpend(
            accountId: demoOpenRouter.id,
            currency: "USD",
            now: now
        )
        let latestBalance = BalanceSnapshot(
            accountId: demoDeepSeek.id,
            currency: "CNY",
            total: 92.40,
            granted: 10,
            toppedUp: 82.40,
            isAvailable: true,
            asOf: now.addingTimeInterval(-120),
            source: "演示数据 · DeepSeek 官方余额模型"
        )
        let engine = AlertEngine(store: store)
        _ = try engine.evaluate(AlertSnapshot(
            accountId: demoDeepSeek.id,
            accountName: demoDeepSeek.displayName,
            provider: .deepseek,
            enabled: true,
            isDemo: true,
            budget: nil,
            monthSpend: nil,
            balanceThreshold: demoDeepSeek.balanceThreshold,
            latestBalance: latestBalance,
            balanceIsFresh: true,
            consecutiveFailures: 0,
            credentialInvalid: false,
            lastSuccessAt: demoDeepSeek.lastSuccessAt,
            lastAttemptAt: demoDeepSeek.lastAttemptAt,
            createdAt: demoDeepSeek.createdAt,
            refreshInterval: 15 * 60,
            usageIsFresh: true,
            now: now
        ))
        let latestUSDBalance = BalanceSnapshot(
            accountId: demoDeepSeekUSD.id,
            currency: "USD",
            total: 32.60,
            granted: 5,
            toppedUp: 27.60,
            isAvailable: true,
            asOf: now.addingTimeInterval(-240),
            source: "演示数据 · DeepSeek 官方余额模型（USD）"
        )
        _ = try engine.evaluate(AlertSnapshot(
            accountId: demoDeepSeekUSD.id,
            accountName: demoDeepSeekUSD.displayName,
            provider: .deepseek,
            enabled: true,
            isDemo: true,
            budget: nil,
            monthSpend: nil,
            balanceThreshold: demoDeepSeekUSD.balanceThreshold,
            latestBalance: latestUSDBalance,
            balanceIsFresh: true,
            consecutiveFailures: 0,
            credentialInvalid: false,
            lastSuccessAt: demoDeepSeekUSD.lastSuccessAt,
            lastAttemptAt: demoDeepSeekUSD.lastAttemptAt,
            createdAt: demoDeepSeekUSD.createdAt,
            refreshInterval: 15 * 60,
            usageIsFresh: true,
            now: now
        ))
        _ = try engine.evaluate(AlertSnapshot(
            accountId: demoOpenRouter.id,
            accountName: demoOpenRouter.displayName,
            provider: .openrouter,
            enabled: true,
            isDemo: true,
            budget: demoOpenRouter.budget,
            monthSpend: monthSpend,
            balanceThreshold: nil,
            latestBalance: nil,
            balanceIsFresh: false,
            consecutiveFailures: 0,
            credentialInvalid: false,
            lastSuccessAt: demoOpenRouter.lastSuccessAt,
            lastAttemptAt: demoOpenRouter.lastAttemptAt,
            createdAt: demoOpenRouter.createdAt,
            refreshInterval: 15 * 60,
            usageIsFresh: true,
            now: now
        ))
        return store
    }

    private static func insertPlatformDemoData(
        store: OverplayStore,
        now: Date
    ) throws {
        for (specIndex, spec) in demoPlatforms.enumerated() {
            let successOffset = -Double(180 + specIndex * 29)
            let account = Account(
                id: spec.id,
                provider: spec.provider,
                name: spec.name,
                enabled: true,
                createdAt: now.addingTimeInterval(-Double(spec.ageDays) * 86_400),
                lastSuccessAt: now.addingTimeInterval(successOffset),
                lastAttemptAt: now.addingTimeInterval(successOffset),
                budget: spec.budget.map { Budget(amount: $0, currency: spec.currency) },
                isDemo: true
            )
            try store.insertAccount(account)

            try store.insertQuotaSnapshot(QuotaSnapshot(
                id: "demo-quota-\(spec.id)",
                accountId: spec.id,
                totalCredits: spec.totalCredits,
                totalUsage: spec.totalUsage,
                remaining: spec.totalCredits - spec.totalUsage,
                currency: spec.currency,
                asOf: now.addingTimeInterval(successOffset),
                source: "演示数据 · \(spec.provider.displayName) 虚拟额度模型"
            ))

            var records: [UsageRecord] = []
            for (dayIndex, day) in lastCompleteUTCDays(now: now).enumerated() {
                let factor = Decimal(75 + (dayIndex * 7 + specIndex * 3) % 50) / 100
                for (modelIndex, model) in spec.models.enumerated() {
                    let requests = 18 + (dayIndex * 5 + specIndex * 11 + modelIndex * 23) % 80
                    records.append(UsageRecord(
                        id: "\(spec.id)-\(day)-\(modelIndex)",
                        accountId: spec.id,
                        accountName: account.displayName,
                        provider: spec.provider,
                        day: day,
                        model: model.name,
                        providerName: model.vendor,
                        promptTokens: scaled(model.prompt, factor),
                        completionTokens: scaled(model.completion, factor),
                        reasoningTokens: model.reasoning == 0 ? nil : scaled(model.reasoning, factor),
                        cachedTokens: modelIndex == 0 ? scaled(model.prompt / 5, factor) : nil,
                        requests: requests,
                        cost: Money.rounded(model.cost * factor, scale: 2),
                        currency: spec.currency,
                        source: "演示数据 · \(spec.provider.displayName) 虚拟用量模型（UTC 日桶）",
                        updatedAt: now.addingTimeInterval(successOffset)
                    ))
                }
            }
            try store.upsertUsage(records, accountName: account.displayName)
        }
    }

    private static func lastCompleteUTCDays(now: Date) -> [String] {
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = CalendarDay.utc
        return (1...30).compactMap { offset in
            guard let date = utcCalendar.date(byAdding: .day, value: -offset, to: now) else {
                return nil
            }
            return CalendarDay.string(for: date, timeZone: CalendarDay.utc, calendar: utcCalendar)
        }
    }

    private static func scaled(_ value: Int, _ factor: Decimal) -> Int {
        NSDecimalNumber(decimal: Decimal(value) * factor).intValue
    }

    private static func dec(_ value: String) -> Decimal {
        Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")) ?? 0
    }

    private static var demoPlatforms: [DemoPlatformSpec] {
        [
            DemoPlatformSpec(
                id: "demo-kimi", provider: .kimi, name: "Kimi 主账户", ageDays: 38,
                currency: "CNY", totalCredits: dec("2000"), totalUsage: dec("1240.50"),
                budget: dec("400"), models: [
                    DemoUsageModel(name: "kimi-k2-0905", vendor: "Moonshot", prompt: 26_000, completion: 7_200, reasoning: 1_800, cost: dec("2.40")),
                    DemoUsageModel(name: "moonshot-v1-128k", vendor: "Moonshot", prompt: 14_000, completion: 3_200, reasoning: 0, cost: dec("0.80"))
                ]
            ),
            DemoPlatformSpec(
                id: "demo-kimi-team", provider: .kimi, name: "Kimi 团队账户", ageDays: 33,
                currency: "CNY", totalCredits: dec("800"), totalUsage: dec("210.20"),
                budget: dec("200"), models: [
                    DemoUsageModel(name: "kimi-k2-turbo", vendor: "Moonshot", prompt: 18_000, completion: 4_600, reasoning: 900, cost: dec("1.30")),
                    DemoUsageModel(name: "moonshot-v1-32k", vendor: "Moonshot", prompt: 9_000, completion: 2_000, reasoning: 0, cost: dec("0.45"))
                ]
            ),
            DemoPlatformSpec(
                id: "demo-glm", provider: .glm, name: "GLM 研发账户", ageDays: 36,
                currency: "CNY", totalCredits: dec("1500"), totalUsage: dec("640.00"),
                budget: dec("300"), models: [
                    DemoUsageModel(name: "glm-4.6", vendor: "Zhipu", prompt: 22_000, completion: 5_400, reasoning: 800, cost: dec("1.60")),
                    DemoUsageModel(name: "glm-4.5-air", vendor: "Zhipu", prompt: 12_000, completion: 2_600, reasoning: 0, cost: dec("0.40"))
                ]
            ),
            DemoPlatformSpec(
                id: "demo-minimax", provider: .minimax, name: "MiniMax 生产账户", ageDays: 35,
                currency: "CNY", totalCredits: dec("1000"), totalUsage: dec("812.40"),
                budget: nil, models: [
                    DemoUsageModel(name: "MiniMax-M2", vendor: "MiniMax", prompt: 20_000, completion: 6_100, reasoning: 1_100, cost: dec("1.90")),
                    DemoUsageModel(name: "abab6.5s-chat", vendor: "MiniMax", prompt: 11_000, completion: 2_400, reasoning: 0, cost: dec("0.55"))
                ]
            ),
            DemoPlatformSpec(
                id: "demo-qwen", provider: .qwen, name: "Qwen 主账户", ageDays: 34,
                currency: "CNY", totalCredits: dec("3000"), totalUsage: dec("1260.75"),
                budget: dec("500"), models: [
                    DemoUsageModel(name: "qwen3-max", vendor: "Alibaba", prompt: 28_000, completion: 6_600, reasoning: 1_200, cost: dec("2.10")),
                    DemoUsageModel(name: "qwen3-coder-plus", vendor: "Alibaba", prompt: 15_000, completion: 3_800, reasoning: 0, cost: dec("0.70"))
                ]
            ),
            DemoPlatformSpec(
                id: "demo-seed", provider: .seed, name: "豆包 Seed 生产", ageDays: 32,
                currency: "CNY", totalCredits: dec("1200"), totalUsage: dec("468.30"),
                budget: nil, models: [
                    DemoUsageModel(name: "doubao-seed-1.6", vendor: "ByteDance", prompt: 24_000, completion: 5_200, reasoning: 700, cost: dec("1.50")),
                    DemoUsageModel(name: "doubao-pro-32k", vendor: "ByteDance", prompt: 13_000, completion: 2_900, reasoning: 0, cost: dec("0.50"))
                ]
            ),
            DemoPlatformSpec(
                id: "demo-hunyuan", provider: .hunyuan, name: "腾讯混元 测试", ageDays: 31,
                currency: "CNY", totalCredits: dec("900"), totalUsage: dec("128.60"),
                budget: nil, models: [
                    DemoUsageModel(name: "hunyuan-t1", vendor: "Tencent", prompt: 16_000, completion: 4_200, reasoning: 600, cost: dec("1.10")),
                    DemoUsageModel(name: "hunyuan-a13b", vendor: "Tencent", prompt: 8_000, completion: 1_800, reasoning: 0, cost: dec("0.30"))
                ]
            ),
            DemoPlatformSpec(
                id: "demo-openai", provider: .openai, name: "OpenAI 生产", ageDays: 30,
                currency: "USD", totalCredits: dec("400"), totalUsage: dec("236.80"),
                budget: dec("250"), models: [
                    DemoUsageModel(name: "gpt-5.2", vendor: "OpenAI", prompt: 22_000, completion: 6_000, reasoning: 1_200, cost: dec("2.60")),
                    DemoUsageModel(name: "gpt-5-mini", vendor: "OpenAI", prompt: 12_000, completion: 3_000, reasoning: 300, cost: dec("0.60"))
                ]
            ),
            DemoPlatformSpec(
                id: "demo-anthropic", provider: .anthropic, name: "Anthropic 研发", ageDays: 29,
                currency: "USD", totalCredits: dec("350"), totalUsage: dec("188.40"),
                budget: dec("200"), models: [
                    DemoUsageModel(name: "claude-sonnet-4.5", vendor: "Anthropic", prompt: 25_000, completion: 6_800, reasoning: 1_500, cost: dec("2.80")),
                    DemoUsageModel(name: "claude-haiku-4.5", vendor: "Anthropic", prompt: 10_000, completion: 2_400, reasoning: 200, cost: dec("0.45"))
                ]
            ),
            DemoPlatformSpec(
                id: "demo-gemini", provider: .gemini, name: "Gemini 分析", ageDays: 28,
                currency: "USD", totalCredits: dec("300"), totalUsage: dec("142.25"),
                budget: nil, models: [
                    DemoUsageModel(name: "gemini-2.5-pro", vendor: "Google", prompt: 26_000, completion: 6_400, reasoning: 1_600, cost: dec("2.20")),
                    DemoUsageModel(name: "gemini-2.5-flash", vendor: "Google", prompt: 12_000, completion: 2_600, reasoning: 0, cost: dec("0.35"))
                ]
            ),
            DemoPlatformSpec(
                id: "demo-meta", provider: .meta, name: "Meta Llama 试验", ageDays: 27,
                currency: "USD", totalCredits: dec("200"), totalUsage: dec("96.40"),
                budget: nil, models: [
                    DemoUsageModel(name: "llama-4-maverick", vendor: "Meta", prompt: 18_000, completion: 4_800, reasoning: 500, cost: dec("1.20")),
                    DemoUsageModel(name: "llama-4-scout", vendor: "Meta", prompt: 9_000, completion: 2_000, reasoning: 0, cost: dec("0.30"))
                ]
            ),
            DemoPlatformSpec(
                id: "demo-xai", provider: .xai, name: "xAI Grok 生产", ageDays: 26,
                currency: "USD", totalCredits: dec("250"), totalUsage: dec("118.70"),
                budget: nil, models: [
                    DemoUsageModel(name: "grok-4", vendor: "xAI", prompt: 21_000, completion: 5_600, reasoning: 1_000, cost: dec("2.00")),
                    DemoUsageModel(name: "grok-3-mini", vendor: "xAI", prompt: 9_000, completion: 2_000, reasoning: 0, cost: dec("0.40"))
                ]
            ),
            DemoPlatformSpec(
                id: "demo-mistral", provider: .mistral, name: "Mistral 备用", ageDays: 25,
                currency: "USD", totalCredits: dec("180"), totalUsage: dec("171.90"),
                budget: dec("120"), models: [
                    DemoUsageModel(name: "mistral-large-3", vendor: "Mistral", prompt: 19_000, completion: 5_000, reasoning: 600, cost: dec("1.70")),
                    DemoUsageModel(name: "codestral-2508", vendor: "Mistral", prompt: 8_000, completion: 1_800, reasoning: 0, cost: dec("0.35"))
                ]
            )
        ]
    }
}
