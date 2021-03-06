import Quick
import Nimble
import PathKit
import SourceKittenFramework
@testable import Sourcery

func build(_ source: String) -> [String: SourceKitRepresentable]? {
    return Structure(file: File(contents: source)).dictionary
}

class ParserSpec: QuickSpec {
    // swiftlint:disable function_body_length
    override func spec() {
        describe("Parser") {
            var sut: Parser?

            beforeEach {
                sut = Parser()
            }

            afterEach {
                sut = nil
            }

            describe("parseVariable") {
                func parse(_ code: String) -> Variable? {
                    _ = sut?.parseContents(code)
                    let code = build(code)
                    guard let substructures = code?[SwiftDocKey.substructure.rawValue] as? [SourceKitRepresentable],
                          let src = substructures.first as? [String: SourceKitRepresentable] else {
                        fail()
                        return nil
                    }
                    return sut?.parseVariable(src)
                }

                it("ignores private variables") {
                    expect(parse("private var name: String")).to(beNil())
                    expect(parse("fileprivate var name: String")).to(beNil())
                }

                it("extracts standard property correctly") {
                    expect(parse("var name: String")).to(equal(Variable(name: "name", typeName: "String", accessLevel: (read: .internal, write: .internal), isComputed: false)))
                }

                it("extracts standard let property correctly") {
                    let r = parse("let name: String")
                    expect(r).to(equal(Variable(name: "name", typeName: "String", accessLevel: (read: .internal, write: .none), isComputed: false)))
                }

                it("extracts computed property correctly") {
                    expect(parse("var name: Int { return 2 }")).to(equal(Variable(name: "name", typeName: "Int", accessLevel: (read: .internal, write: .none), isComputed: true)))
                }

                it("extracts generic property correctly") {
                    expect(parse("let name: Observable<Int>")).to(equal(Variable(name: "name", typeName: "Observable<Int>", accessLevel: (read: .internal, write: .none), isComputed: false)))
                }

                it("extracts property with didSet correctly") {
                    expect(parse(
                            "var name: Int? {\n" +
                                    "didSet { _ = 2 }\n" +
                                    "willSet { _ = 4 }\n" +
                                    "}")).to(equal(Variable(name: "name", typeName: "Int?", accessLevel: (read: .internal, write: .internal), isComputed: false)))
                }

                context("given it has sourcery annotations") {

                    it("extracts single annotation") {
                        let expectedVariable = Variable(name: "name", typeName: "Int", accessLevel: (read: .internal, write: .none), isComputed: true)
                        expectedVariable.annotations["skipEquability"] = NSNumber(value: true)

                        expect(parse("// sourcery: skipEquability\n" +
                                             "var name: Int { return 2 }")).to(equal(expectedVariable))
                    }

                    it("extracts multiple annotations on the same line") {
                        let expectedVariable = Variable(name: "name", typeName: "Int", accessLevel: (read: .internal, write: .none), isComputed: true)
                        expectedVariable.annotations["skipEquability"] = NSNumber(value: true)
                        expectedVariable.annotations["jsonKey"] = "json_key" as NSString

                        expect(parse("// sourcery: skipEquability, jsonKey = \"json_key\"\n" +
                                             "var name: Int { return 2 }")).to(equal(expectedVariable))
                    }

                    it("extracts multi-line annotations, including numbers") {
                        let expectedVariable = Variable(name: "name", typeName: "Int", accessLevel: (read: .internal, write: .none), isComputed: true)
                        expectedVariable.annotations["skipEquability"] = NSNumber(value: true)
                        expectedVariable.annotations["jsonKey"] = "json_key" as NSString
                        expectedVariable.annotations["thirdProperty"] = NSNumber(value: -3)

                        let result = parse(        "// sourcery: skipEquability, jsonKey = \"json_key\"\n" +
                                                           "// sourcery: thirdProperty = -3\n" +
                                                           "var name: Int { return 2 }")
                        expect(result).to(equal(expectedVariable))
                    }

                    it("extracts annotations interleaved with comments") {
                        let expectedVariable = Variable(name: "name", typeName: "Int", accessLevel: (read: .internal, write: .none), isComputed: true)
                        expectedVariable.annotations["isSet"] = NSNumber(value: true)
                        expectedVariable.annotations["numberOfIterations"] = NSNumber(value: 2)

                        let result = parse(        "// sourcery: isSet\n" +
                                                           "/// isSet is used for something useful\n" +
                                                           "// sourcery: numberOfIterations = 2\n" +
                                                           "var name: Int { return 2 }")
                        expect(result).to(equal(expectedVariable))
                    }

                    it("stops extracting annotations if it encounters a non-comment line") {
                        let expectedVariable = Variable(name: "name", typeName: "Int", accessLevel: (read: .internal, write: .none), isComputed: true)
                        expectedVariable.annotations["numberOfIterations"] = NSNumber(value: 2)

                        let result = parse(        "// sourcery: isSet\n" +
                                                           "\n" +
                                                           "// sourcery: numberOfIterations = 2\n" +
                                                           "var name: Int { return 2 }")
                        expect(result).to(equal(expectedVariable))
                    }
                }
            }

            describe("parseTypes") {
                func parse(_ code: String, existingTypes: [Type] = []) -> [Type] {
                    let parserResult = sut?.parseContents(code, existingTypes: (existingTypes, [])) ?? ([], [])
                    return sut?.uniqueTypes(parserResult) ?? []
                }

                context("given it has sourcery annotations") {
                    it("extracts annotation block") {
                        let annotations = [
                                ["skipEquality" : NSNumber(value: true)],
                                ["skipEquality" : NSNumber(value: true), "extraAnnotation" : NSNumber(value: Float(2))],
                                [:]
                        ]
                        let expectedVariables = (1...3)
                                .map { Variable(name: "property\($0)", typeName: "Int", annotations: annotations[$0 - 1]) }
                        let expectedType = Type(name: "Foo", variables: expectedVariables, annotations: ["skipEquality" : NSNumber(value: true)])

                        let result = parse("// sourcery:begin: skipEquality\n\n\n\n" +
                                "class Foo {\n" +
                                "  var property1: Int\n\n\n" +
                                " // sourcery: extraAnnotation = 2\n" +
                                "  var property2: Int\n\n" +
                                "  // sourcery:end\n" +
                                "  var property3: Int\n" +
                                "}")
                        expect(result).to(equal([expectedType]))
                    }
                }

                context("given struct") {
                    it("ignores private structs") {
                        expect(parse("private struct Foo {}")).to(beEmpty())
                        expect(parse("fileprivate struct Foo {}")).to(beEmpty())
                    }

                    it("extracts properly") {
                        expect(parse("struct Foo { }"))
                                .to(equal([
                                        Struct(name: "Foo", accessLevel: .internal, isExtension: false, variables: [])
                                ]))
                    }

                    it("extracts generic struct properly") {
                        expect(parse("struct Foo<Something> { }"))
                                .to(equal([
                                    Struct(name: "Foo", isGeneric: true)
                                          ]))
                    }

                    it("extracts instance variables properly") {
                        expect(parse("struct Foo { var x: Int }"))
                                .to(equal([
                                                  Struct(name: "Foo", accessLevel: .internal, isExtension: false, variables: [Variable.init(name: "x", typeName: "Int", accessLevel: (read: .internal, write: .internal), isComputed: false)])
                                          ]))
                    }

                    it("extracts class variables properly") {
                        expect(parse("struct Foo { static var x: Int { return 2 }; class var y: Int = 0 }"))
                                .to(equal([
                                    Struct(name: "Foo", accessLevel: .internal, isExtension: false, variables: [
                                        Variable.init(name: "x", typeName: "Int", accessLevel: (read: .internal, write: .none), isComputed: true, isStatic: true),
                                        Variable.init(name: "y", typeName: "Int", accessLevel: (read: .internal, write: .internal), isComputed: false, isStatic: true)
                                        ])
                                    ]))
                    }

                    context("given nested struct") {
                        it("extracts properly") {
                            let innerType = Struct(name: "Bar", accessLevel: .internal, isExtension: false, variables: [])

                            expect(parse("public struct Foo { struct Bar { } }"))
                                    .to(equal([
                                            Struct(name: "Foo", accessLevel: .public, isExtension: false, variables: [], containedTypes: [innerType]),
                                            innerType
                                    ]))
                        }
                    }
                }

                context("given class") {
                    it("ignores private classes") {
                        expect(parse("private class Foo {}")).to(beEmpty())
                        expect(parse("fileprivate class Foo {}")).to(beEmpty())
                    }

                    it("extracts variables properly") {
                        expect(parse("class Foo { }; extension Foo { var x: Int }"))
                                .to(equal([
                                        Type(name: "Foo", accessLevel: .internal, isExtension: false, variables: [Variable.init(name: "x", typeName: "Int", accessLevel: (read: .internal, write: .internal), isComputed: false)])
                                ]))
                    }

                    it("extracts inherited types properly") {
                        expect(parse("class Foo: TestProtocol { }; extension Foo: AnotherProtocol {}"))
                                .to(equal([
                                        Type(name: "Foo", accessLevel: .internal, isExtension: false, variables: [], inheritedTypes: ["AnotherProtocol", "TestProtocol"])
                                ]))
                    }

                    it("extracts annotations correctly") {
                        let expectedType = Type(name: "Foo", accessLevel: .internal, isExtension: false, variables: [], inheritedTypes: ["TestProtocol"])
                        expectedType.annotations["firstLine"] = NSNumber(value: true)
                        expectedType.annotations["thirdLine"] = NSNumber(value: 4543)

                        expect(parse("// sourcery: thirdLine = 4543\n/// comment\n// sourcery: firstLine\n class Foo: TestProtocol { }"))
                                .to(equal([expectedType]))
                    }
                }

                context("given unknown type") {
                    it("extracts extensions properly") {
                        expect(parse("protocol Foo { }; extension Bar: Foo { var x: Int { return 0 } }"))
                            .to(equal([
                                Type(name: "Bar", accessLevel: .none, isExtension: true, variables: [Variable.init(name: "x", typeName: "Int", accessLevel: (read: .internal, write: .none), isComputed: true)], inheritedTypes: ["Foo"]),
                                Protocol(name: "Foo")
                                ]))
                    }
                }

                context("given typealias") {
                    it("ignores private typealiases") {
                        expect(sut?.parseContents("private typealias Alias = String").typealiases).to(beEmpty())

                        expect(sut?.parseContents("fileprivate typealias Alias = String").typealiases).to(beEmpty())
                    }

                    context("given global typealias") {
                        it("extracts global typealiases properly") {
                            expect(sut?.parseContents("typealias GlobalAlias = Foo; class Foo { typealias FooAlias = Int; class Bar { typealias BarAlias = Int } }").typealiases)
                                .to(equal([
                                    Typealias(aliasName: "GlobalAlias", typeName: "Foo")
                                    ]))
                        }

                        it("extracts typealiases for inner types") {
                            expect(sut?.parseContents("typealias GlobalAlias = Foo.Bar;").typealiases)
                                .to(equal([
                                    Typealias(aliasName: "GlobalAlias", typeName: "Foo.Bar")
                                    ]))
                        }

                        it("extracts typealiases of other typealiases") {
                            expect(sut?.parseContents("typealias Foo = Int; typealias Bar = Foo").typealiases)
                                .to(contain([
                                    Typealias(aliasName: "Foo", typeName: "Int"),
                                    Typealias(aliasName: "Bar", typeName: "Foo"),
                                    ]))
                        }

                        it("replaces variable alias with actual type via 3 typealiases") {
                            let expectedVariable = Variable(name: "foo", typeName: "FinalAlias")
                            expectedVariable.type = Type(name: "Foo")

                            let type = parse("typealias FooAlias = Foo; typealias BarAlias = FooAlias; typealias FinalAlias = BarAlias; class Foo {}; class Bar { var foo: FinalAlias }").first
                            let variable = type?.variables.first

                            expect(variable).to(equal(expectedVariable))
                            expect(variable?.type).to(equal(expectedVariable.type))
                        }

                        it("replaces variable alias type with actual type") {
                            let expectedVariable = Variable(name: "foo", typeName: "GlobalAlias")
                            expectedVariable.type = Type(name: "Foo")

                            let type = parse("typealias GlobalAlias = Foo; class Foo {}; class Bar { var foo: GlobalAlias }").first
                            let variable = type?.variables.first

                            expect(variable).to(equal(expectedVariable))
                            expect(variable?.type).to(equal(expectedVariable.type))
                        }

                        it("replaces variable optional alias type with actual type") {
                            let expectedVariable = Variable(name: "foo", typeName: "GlobalAlias?")
                            expectedVariable.type = Type(name: "Foo")

                            let type = parse("typealias GlobalAlias = Foo; class Foo {}; class Bar { var foo: GlobalAlias? }").first
                            let variable = type?.variables.first

                            expect(variable).to(equal(expectedVariable))
                            expect(variable?.type).to(equal(expectedVariable.type))
                        }

                        it("extends actual type with type alias extension") {
                            expect(parse("typealias GlobalAlias = Foo; class Foo: TestProtocol { }; extension GlobalAlias: AnotherProtocol {}"))
                                .to(equal([
                                    Type(name: "Foo", accessLevel: .internal, isExtension: false, variables: [], inheritedTypes: ["AnotherProtocol", "TestProtocol"])
                                    ]))
                        }

                        it("updates inheritedTypes with real type name") {
                            expect(parse("typealias GlobalAliasFoo = Foo; class Foo { }; class Bar: GlobalAliasFoo {}"))
                                .to(contain([
                                    Type(name: "Bar", inheritedTypes: ["Foo"])
                                    ]))
                        }

                    }

                    context("given local typealias") {
                        it ("extracts local typealiases properly") {
                            let foo = Type(name: "Foo")
                            let bar = Type(name: "Bar", parent: foo)
                            let fooBar = Type(name: "FooBar", parent: bar)

                            let types = sut?.parseContents("class Foo { typealias FooAlias = String; struct Bar { typealias BarAlias = Int; struct FooBar { typealias FooBarAlias = Float } } }").types

                            let fooAliases = types?.first?.typealiases
                            let barAliases = types?.first?.containedTypes.first?.typealiases
                            let fooBarAliases = types?.first?.containedTypes.first?.containedTypes.first?.typealiases

                            expect(fooAliases).to(equal(["FooAlias": Typealias(aliasName: "FooAlias", typeName: "String", parent: foo)]))
                            expect(barAliases).to(equal(["BarAlias": Typealias(aliasName: "BarAlias", typeName: "Int", parent: bar)]))
                            expect(fooBarAliases).to(equal(["FooBarAlias": Typealias(aliasName: "FooBarAlias", typeName: "Float", parent: fooBar)]))
                        }

                        it("replaces variable alias type with actual type") {
                            let expectedVariable = Variable(name: "foo", typeName: "FooAlias")
                            expectedVariable.type = Type(name: "Foo")

                            let type = parse("class Bar { typealias FooAlias = Foo; var foo: FooAlias }; class Foo {}").first
                            let variable = type?.variables.first

                            expect(variable).to(equal(expectedVariable))
                            expect(variable?.type).to(equal(expectedVariable.type))
                        }

                        it("replaces variable alias type with actual contained type") {
                            let expectedVariable = Variable(name: "foo", typeName: "FooAlias")
                            expectedVariable.type = Type(name: "Foo", parent: Type(name: "Bar"))

                            let type = parse("class Bar { typealias FooAlias = Foo; var foo: FooAlias; class Foo {} }").first
                            let variable = type?.variables.first

                            expect(variable).to(equal(expectedVariable))
                            expect(variable?.type).to(equal(expectedVariable.type))
                        }

                        it("replaces variable alias type with actual foreign contained type") {
                            let expectedVariable = Variable(name: "foo", typeName: "FooAlias")
                            expectedVariable.type = Type(name: "Foo", parent: Type(name: "FooBar"))

                            let type = parse("class Bar { typealias FooAlias = FooBar.Foo; var foo: FooAlias }; class FooBar { class Foo {} }").first
                            let variable = type?.variables.first

                            expect(variable).to(equal(expectedVariable))
                            expect(variable?.type).to(equal(expectedVariable.type))
                        }

                    }

                }

                context("given enum") {
                    it("ignores private enums") {
                        expect(parse("private enum Foo {}")).to(beEmpty())
                        expect(parse("fileprivate enum Foo {}")).to(beEmpty())
                    }

                    it("extracts empty enum properly") {
                        expect(parse("enum Foo { }"))
                                .to(equal([
                                        Enum(name: "Foo", accessLevel: .internal, isExtension: false, inheritedTypes: [], cases: [])
                                ]))
                    }

                    it("extracts cases properly") {
                        expect(parse("enum Foo { case optionA; case optionB }"))
                                .to(equal([
                                        Enum(name: "Foo", accessLevel: .internal, isExtension: false, inheritedTypes: [], cases: [Enum.Case(name: "optionA"), Enum.Case(name: "optionB")])
                                ]))
                    }

                    it("extracts multi-byte cases properly") {
                        expect(parse("enum JapaneseEnum {\ncase アイウエオ\n}"))
                            .to(equal([
                                Enum(name: "JapaneseEnum", cases: [Enum.Case(name: "アイウエオ")])
                                ]))
                    }

                    it("extracts cases with annotations properly") {
                        expect(parse("enum Foo {\n // sourcery: annotation\ncase optionA(Int)\n case optionB }"))
                                .to(equal([
                                        Enum(name: "Foo", cases: [Enum.Case(name: "optionA",
                                                associatedValues: [Enum.Case.AssociatedValue(name: "0", typeName: "Int")],
                                                annotations: ["annotation": NSNumber(value: true)]), Enum.Case(name: "optionB")])
                                ]))
                    }

                    it("extracts variables properly") {
                        expect(parse("enum Foo { var x: Int { return 1 } }"))
                                .to(equal([
                                        Enum(name: "Foo", accessLevel: .internal, isExtension: false, inheritedTypes: [], cases: [], variables: [Variable(name: "x", typeName: "Int", accessLevel: (.internal, .none), isComputed: true)])
                                ]))
                    }

                    context("given enum without rawType") {
                        it("extracts inherited types properly") {
                            expect(parse("enum Foo: SomeProtocol { case optionA }; protocol SomeProtocol {}"))
                                .to(equal([
                                    Enum(name: "Foo", accessLevel: .internal, isExtension: false, inheritedTypes: ["SomeProtocol"], rawType: nil, cases: [Enum.Case(name: "optionA")]),
                                    Protocol(name: "SomeProtocol")
                                    ]))
                        }

                        it("extracts types inherited in extension properly") {
                            expect(parse("enum Foo { case optionA }; extension Foo: SomeProtocol {}; protocol SomeProtocol {}"))
                                .to(equal([
                                    Enum(name: "Foo", accessLevel: .internal, isExtension: false, inheritedTypes: ["SomeProtocol"], rawType: nil, cases: [Enum.Case(name: "optionA")]),
                                    Protocol(name: "SomeProtocol")
                                    ]))
                        }
                    }

                    context("given enum containing rawType") {

                        it("extracts enums without RawRepresentable") {
                            expect(parse("enum Foo: String, SomeProtocol { case optionA }; protocol SomeProtocol {}"))
                                .to(equal([
                                    Enum(name: "Foo", accessLevel: .internal, isExtension: false, inheritedTypes: ["SomeProtocol"], rawType: "String", cases: [Enum.Case(name: "optionA")]),
                                    Protocol(name: "SomeProtocol")
                                    ]))
                        }

                        it("extracts enums with RawRepresentable by inferring from variable") {
                            expect(parse("enum Foo: RawRepresentable { case optionA; var rawValue: String { return \"\" }; init?(rawValue: String) { self = .optionA } }")).to(equal([
                                Enum(name: "Foo", accessLevel: .internal, isExtension: false, inheritedTypes: ["RawRepresentable"], rawType: "String", cases: [Enum.Case(name: "optionA")], variables: [Variable(name: "rawValue", typeName: "String", accessLevel: (read: .internal, write: .none), isComputed: true, isStatic: false)])
                                ]))
                        }

                        it("extracts enums with RawRepresentable by inferring from variable with typealias") {
                            expect(parse("enum Foo: RawRepresentable { case optionA; typealias RawValue = String; var rawValue: RawValue { return \"\" }; init?(rawValue: RawValue) { self = .optionA } }")).to(equal([
                                Enum(name: "Foo", accessLevel: .internal, isExtension: false, inheritedTypes: ["RawRepresentable"], rawType: "String", cases: [Enum.Case(name: "optionA")], variables: [Variable(name: "rawValue", typeName: "RawValue", accessLevel: (read: .internal, write: .none), isComputed: true, isStatic: false)], typealiases: [Typealias(aliasName: "RawValue", typeName: "String")])
                                ]))
                        }

                        it("extracts enums with RawRepresentable by inferring from typealias") {
    						expect(parse("enum Foo: CustomStringConvertible, RawRepresentable { case optionA; typealias RawValue = String; var rawValue: RawValue { return \"\" }; init?(rawValue: RawValue) { self = .optionA } }")).to(equal([
                                Enum(name: "Foo", accessLevel: .internal, isExtension: false, inheritedTypes: ["CustomStringConvertible", "RawRepresentable"], rawType: "String", cases: [Enum.Case(name: "optionA")], variables: [Variable(name: "rawValue", typeName: "RawValue", accessLevel: (read: .internal, write: .none), isComputed: true, isStatic: false)], typealiases: [Typealias(aliasName: "RawValue", typeName: "String")])
                                ]))
                        }

                        it("extracts enums with custom values") {
                            expect(parse("enum Foo: String { case optionA = \"Value\" }"))
                                .to(equal([
                                    Enum(name: "Foo", accessLevel: .internal, isExtension: false, rawType: "String", cases: [Enum.Case(name: "optionA", rawValue: "Value")])
                                    ]))
                        }
                    }

                    it("extracts enums without rawType") {
                        let expectedEnum = Enum(name: "Foo", accessLevel: .internal, isExtension: false, inheritedTypes: [], cases: [Enum.Case(name: "optionA")])

                        expect(parse("enum Foo { case optionA }")).to(equal([expectedEnum]))
                    }

                    it("extracts enums with associated types") {
                        expect(parse("enum Foo { case optionA(Observable<Int>); case optionB(named: Float) }"))
                                .to(equal([
                                    Enum(name: "Foo", accessLevel: .internal, isExtension: false, inheritedTypes: [], cases:
                                        [
                                            Enum.Case(name: "optionA", associatedValues: [Enum.Case.AssociatedValue(name: "0", typeName: "Observable<Int>")]),
                                            Enum.Case(name: "optionB", associatedValues: [Enum.Case.AssociatedValue(name: "named", typeName: "Float")])
                                        ])
                                ]))
                    }

                    it("extracts enums with empty parenthesis as ones without associated type") {
                        expect(parse("enum Foo { case optionA(); case optionB() }"))
                                .to(equal([
                                                  Enum(name: "Foo", accessLevel: .internal, isExtension: false, inheritedTypes: [], cases:
                                                  [
                                                          Enum.Case(name: "optionA", associatedValues: []),
                                                          Enum.Case(name: "optionB", associatedValues: [])
                                                  ])
                                          ]))
                    }
                }

                context("given protocol") {
                    it("ignores private protocols") {
                        expect(parse("private protocol Foo {}")).to(beEmpty())
                        expect(parse("fileprivate protocol Foo {}")).to(beEmpty())
                    }

                    it("extracts empty protocol properly") {
                        expect(parse("protocol Foo { }"))
                            .to(equal([
                                Protocol(name: "Foo")
                                ]))
                    }
                }

                context("given extension") {
                    it("ignores extension for private type") {
                        expect(parse("private struct Foo {}; extension Foo { var x: Int { return 0 } }")).to(beEmpty())
                        expect(parse("fileprivate struct Foo {}; extension Foo { var x: Int { return 0 } }")).to(beEmpty())
                    }
                }

                context("given existing types") {
                    let existingType = Type(name: "Bar", accessLevel: .internal, isExtension: false, variables: [], inheritedTypes: ["TestProtocol"])

                    it("combines properly") {
                        expect(parse("struct Foo { }", existingTypes: [existingType]))
                                .to(equal([existingType, Struct(name: "Foo")]))
                    }
                }
            }

            describe("parseFile") {
                it("ignores files that are marked with Generated by Sourcery, returning previous types") {
                    let existingTypes: [Type] = [Type(name: "Bar", accessLevel: .internal, isExtension: false, variables: [], inheritedTypes: ["TestProtocol"])]
                    var updatedTypes: [Type]?

                    expect { updatedTypes = try sut?.parseFile(Stubs.resultDirectory + Path("Basic.swift"), existingTypes: (existingTypes, [])).types }.toNot(throwError())

                    expect(updatedTypes).to(equal(existingTypes))
                }
            }
        }
    }
}
