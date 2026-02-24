import AppIntents

struct PoemPageIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Poem Page"
    static var description = IntentDescription("Choose which page of today's poem to show in this widget.")

    @Parameter(title: "Page Number", default: 1)
    var pageNumber: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Show page \(\.$pageNumber)")
    }
}
