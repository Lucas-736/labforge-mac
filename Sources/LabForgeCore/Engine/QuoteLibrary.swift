import Foundation

/// Curated research & lab quotes. Selection is deterministic per calendar day.
public enum QuoteLibrary: Sendable {

    public static let allQuotes: [ResearchQuote] = [
        q("hu-shi", "大胆假设，小心求证。", "胡适", "方法"),
        q("zhongyong", "博学之，审问之，慎思之，明辨之，笃行之。", "《礼记·中庸》", "治学"),
        q("lisao", "路漫漫其修远兮，吾将上下而求索。", "屈原《离骚》", "坚持"),
        q("quanxue-steps", "不积跬步，无以至千里；不积小流，无以成江海。", "荀子《劝学》", "积累"),
        q("quanxue-carve", "锲而舍之，朽木不折；锲而不舍，金石可镂。", "荀子《劝学》", "坚持"),
        q("lu-you", "纸上得来终觉浅，绝知此事要躬行。", "陆游", "实验"),
        q("zhu-xi", "问渠那得清如许？为有源头活水来。", "朱熹", "阅读"),
        q("marx", "在科学上没有平坦的大道，只有不畏劳苦沿着陡峭山路攀登的人，才有希望达到光辉的顶点。", "马克思", "坚持"),
        q("jingshi", "宝剑锋从磨砺出，梅花香自苦寒来。", "《警世贤文》", "坚持"),
        q("brecht", "科学的唯一目的，是减轻人类生存的苦难。", "布莱希特《伽利略传》", "初心"),
        q("pasteur", "Chance favors only the prepared mind.\n机遇只偏爱有准备的头脑。", "Louis Pasteur", "准备"),
        q("curie", "Nothing in life is to be feared, it is only to be understood.\n生活中没有什么可怕的东西，只有需要理解的东西。", "Marie Curie", "勇气"),
        q("newton", "If I have seen further, it is by standing on the shoulders of giants.\n如果说我看得更远，那是因为我站在巨人的肩膀上。", "Isaac Newton", "阅读"),
        q("feynman-fool", "The first principle is that you must not fool yourself — and you are the easiest person to fool.\n第一原则是不要欺骗自己，而你恰恰是最容易被欺骗的人。", "Richard Feynman", "严谨"),
        q("feynman-create", "What I cannot create, I do not understand.\n我不能创造的，我就不理解。", "Richard Feynman", "理解"),
        q("szent-gyorgyi", "Research is to see what everybody else has seen, and to think what nobody else has thought.\n研究，就是看见人人都见过的，想到无人想过的。", "Albert Szent-Györgyi", "创新"),
        q("sagan", "Science is a way of thinking much more than it is a body of knowledge.\n科学与其说是一套知识，不如说是一种思考方式。", "Carl Sagan", "思考"),
        q("einstein", "The important thing is not to stop questioning.\n重要的是不要停止提问。", "Albert Einstein", "好奇"),
        q("tyson", "The good thing about science is that it's true whether or not you believe in it.\n科学的好处在于，无论你信不信，它都是真的。", "Neil deGrasse Tyson", "求真"),
        q("lf-western", "失败的实验也是数据，它在告诉你下一次该调整哪一步。", "LabForge", "实验"),
        q("lf-control", "今天认真做的阴性对照，是明天结论的底气。", "LabForge", "严谨"),
        q("lf-notebook", "把实验记录写清楚，是对三个月后的自己最大的温柔。", "LabForge", "记录"),
        q("lf-centrifuge", "离心机转起来的时候，你也可以停下来喝口水。", "LabForge", "节奏"),
        q("lf-repro", "慢一点没关系，可重复才是科研真正的速度。", "LabForge", "严谨"),
        q("lf-question", "一个好问题，比十张漂亮的图更值钱。", "LabForge", "思考"),
        q("lf-detail", "代码报错和细胞污染一样，都是在提醒你回到细节。", "LabForge", "细节"),
        q("lf-papers", "读文献不是为了记住一切，而是为了知道下一步该问什么。", "LabForge", "阅读"),
        q("lf-variable", "今天也许没有突破，但你离答案又近了一个变量。", "LabForge", "坚持"),
        q("lf-cumulative", "Progress in the lab is rarely linear — but it is always cumulative.\n实验室里的进展很少是线性的，但它总在累积。", "LabForge", "积累"),
        q("lf-slice", "把大课题拆成今天能完成的一小步，然后只管把这一步做好。", "LabForge", "方法"),
        q("lf-patience", "Good science is mostly patience, wearing a lab coat.\n好的科研，多半是穿着白大褂的耐心。", "LabForge", "耐心"),
        q("lf-sleep", "睡眠也是实验方案的一部分。", "LabForge", "节奏"),
        q("lf-low-day", "允许自己有低产出的一天，但别放弃有记录的一天。", "LabForge", "记录"),
    ]

    private static func q(_ id: String, _ text: String, _ author: String, _ tag: String) -> ResearchQuote {
        ResearchQuote(id: id, text: text, author: author, tag: tag)
    }

    /// Same quote for every moment of a calendar day; cycles through the library day by day.
    public static func dailyQuote(for date: Date = Date(), calendar: Calendar = .current) -> ResearchQuote {
        var ref = DateComponents()
        ref.year = 2024
        ref.month = 1
        ref.day = 1
        let refDay = calendar.date(from: ref).map { calendar.startOfDay(for: $0) } ?? Date(timeIntervalSince1970: 0)
        let days = calendar.dateComponents([.day], from: refDay, to: calendar.startOfDay(for: date)).day ?? 0
        let n = allQuotes.count
        return allQuotes[((days % n) + n) % n]
    }

    /// The quote following `id` (wrapping around). Unknown ids return the first quote.
    public static func nextQuote(after id: String) -> ResearchQuote {
        guard let i = allQuotes.firstIndex(where: { $0.id == id }) else { return allQuotes[0] }
        return allQuotes[(i + 1) % allQuotes.count]
    }
}
