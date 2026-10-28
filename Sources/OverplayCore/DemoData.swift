import Foundation

public enum DemoMode {
    public static let disclaimer = """
    演示模式中的厂商数据、用量、费用、余额、额度、进度与告警均为模拟数据，仅用于展示产品功能，不代表任何真实账户、账单或消耗，不构成财务、税务、法律或投资建议。请勿将演示数据用于对账、报销、预算或其他实际决策；实际数据以各厂商官方控制台及账单为准。演示模式不会连接任何厂商接口，也不会读取或写入真实凭证。
    """

    public static let shortBadge = "演示数据 · 仅作功能展示，不代表真实账单"
}

public enum DemoData {
    public static func makeStore(now: Date = Date()) throws -> OverplayStore {
        let store = try OverplayStore.inMemory()
        let calendar = Calendar.current
        let demoDeepSeek = Account(
            id: "demo-deepseek",
            provider: .deepseek,
            name: "DeepSeek 演示账户",
            enabled: true,
            createdAt: now.addingTimeInterval(-40 * 86_400),
            lastSuccessAt: now.addingTimeInterval(-120),
            lastAttemptAt: now.addingTimeInterval(-120),
            balanceThreshold: BalanceThreshold(amount: 100, currency: "CNY"),
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
            isDemo: true
        )
        try store.insertAccount(demoDeepSeek)
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
        for dayOffset in 0..<30 {
            let date = calendar.date(byAdding: .day, value: -dayOffset, to: now) ?? now
            let day = CalendarDay.string(for: date, timeZone: CalendarDay.utc, calendar: calendar)
            if dayOffset % 9 == 8 { continue }
            let factor = 0.8 + Decimal(dayOffset % 5) * 0.1
            for (modelIndex, model) in models.enumerated() {
                let requests = 40 + dayOffset * 3 + modelIndex * 17
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
                    byokCost: dayOffset % 4 == 0 && modelIndex == 1 ? Decimal(string: "0.12")! : nil,
                    currency: "USD",
                    source: "演示数据 · OpenRouter activity 模型（UTC 日桶）",
                    updatedAt: now.addingTimeInterval(-300)
                ))
            }
        }
        try store.upsertUsage(usage, accountName: demoOpenRouter.displayName)

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
}
