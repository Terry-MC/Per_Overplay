import Foundation
import Darwin

@main
struct ResolverTests {
    static var failures = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            print("ok - \(message)")
        } else {
            failures += 1
            print("FAIL - \(message)")
        }
    }

    static func main() {
        let json: [String: Any] = [
            "is_available": true,
            "balance_infos": [
                ["currency": "CNY", "total_balance": "123.45"]
            ],
            "nested": [
                "num": 42,
                "double": 1.5,
                "nullv": NSNull()
            ],
            "weird.key": "dotted",
            "arr": [1, 2, 3]
        ]

        expect(JSONPath.value(at: "balance_infos[0].total_balance", in: json) as? String == "123.45",
               "dot and index path")
        expect(JSONPath.value(at: "is_available", in: json) as? Bool == true,
               "boolean path")
        expect(JSONPath.value(at: "nested.num", in: json) as? Int == 42,
               "integer path")
        expect(JSONPath.value(at: "arr[2]", in: json) as? Int == 3,
               "array index path")
        expect(JSONPath.value(at: "arr[5]", in: json) == nil,
               "array out of bounds is nil")
        expect(JSONPath.value(at: "nested.missing", in: json) == nil,
               "missing key is nil")
        expect(JSONPath.value(at: "[\"weird.key\"]", in: json) as? String == "dotted",
               "quoted bracket key")
        expect(JSONPath.value(at: "", in: json) is [String: Any],
               "empty path returns root")

        expect(ValueFormatter.display(true, prefix: nil, suffix: nil) == "是",
               "bool display")
        expect(ValueFormatter.display(42, prefix: nil, suffix: nil) == "42",
               "int display")
        expect(ValueFormatter.display(NSNull(), prefix: nil, suffix: nil) == "—",
               "null display")
        expect(ValueFormatter.display(nil, prefix: "$", suffix: nil) == "—",
               "nil display ignores prefix")
        expect(ValueFormatter.display(1234, prefix: "$", suffix: nil) == "$1,234",
               "prefix and grouping")
        expect(ValueFormatter.display(nil, prefix: nil, suffix: nil) == "—",
               "missing value display")

        let expanded = Placeholders.expand("Bearer ${apiKey}", apiKey: "sk-test")
        expect(expanded == "Bearer sk-test", "api key placeholder expansion")

        let template = ConfigStore.templateJSON
        do {
            let decoded = try JSONDecoder().decode(OverlayConfig.self, from: Data(template.utf8))
            expect(decoded.vendors?.count == 3, "template decodes three vendors")
            expect(ConfigValidation.validate(decoded) == nil, "template validates")
        } catch {
            failures += 1
            print("FAIL - template JSON decode: \(error)")
        }

        if failures == 0 {
            print("resolver tests passed")
            exit(0)
        } else {
            print("\(failures) test(s) failed")
            exit(1)
        }
    }
}
