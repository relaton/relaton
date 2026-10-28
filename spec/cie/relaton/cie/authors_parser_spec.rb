require "spec_helper"

RSpec.describe Relaton::Cie::AuthorsParser do
  # The twelve forms documented in relaton-cie#5, from the CIE publications
  # pages: the comma separates authors and marks the surname/forename
  # boundary, so the parse is a walk of comma-separated segments.
  def parse(string)
    described_class.parse(string).map { |a| [a.surname, a.forenames, a.completename].compact }
  end

  it "pairs single-word surnames with the following forename" do
    expect(parse("Hemphälä, Hillevi, Glimne Susanne, Heiden, Marina, " \
                 "Lindén, Johannes, Lindberg, Per, Nylén, Per"))
      .to eq [
        ["Hemphälä", ["Hillevi"]],
        ["Glimne Susanne"],
        ["Heiden", ["Marina"]],
        ["Lindén", ["Johannes"]],
        ["Lindberg", ["Per"]],
        ["Nylén", ["Per"]],
      ]
  end

  it "pairs surnames with initials" do
    expect(parse("Chernyak, A.Sh., Fedorishchev, M.A., Kuznetsova, A.B."))
      .to eq [["Chernyak", ["A.Sh."]], ["Fedorishchev", ["M.A."]], ["Kuznetsova", ["A.B."]]]
  end

  it "binds trailing initials to a compound surname" do
    expect(parse("Baradaran-Razaz, N., Merschbrock, C., Jägerbrand, A.K., Nilsson Tengelin, M."))
      .to eq [
        ["Baradaran-Razaz", ["N."]],
        ["Merschbrock", ["C."]],
        ["Jägerbrand", ["A.K."]],
        ["Nilsson Tengelin", ["M."]],
      ]
  end

  it "pairs a surname with multi-word forenames" do
    expect(parse("Dotreppe, Guillaume Mario, Coosemans, Jan, Jacobs, Valéry Ann"))
      .to eq [["Dotreppe", ["Guillaume Mario"]], ["Coosemans", ["Jan"]], ["Jacobs", ["Valéry Ann"]]]
  end

  it "keeps a multi-word run whole when the comma structure gives no boundary" do
    expect(parse("Ulrika Wänström Lindh, Annika K. Jägerbrand"))
      .to eq [["Ulrika Wänström Lindh"], ["Annika K. Jägerbrand"]]
  end

  it "keeps camel-case surnames with initials" do
    expect(parse("AbouElhamd, A.R., Saraiji, R."))
      .to eq [["AbouElhamd", ["A.R."]], ["Saraiji", ["R."]]]
  end

  it "drops the et al. tail" do
    expect(parse("Becak, P., Novak, T. et al."))
      .to eq [["Becak", ["P."]], ["Novak", ["T."]]]
  end

  it "keeps bare Forename Surname runs whole" do
    expect(parse("Georgy Boos, Vladimir Budak, Ekaterina Ilyina, Tatyana Meshkova"))
      .to eq [["Georgy Boos"], ["Vladimir Budak"], ["Ekaterina Ilyina"], ["Tatyana Meshkova"]]
  end

  it "parses initials without a trailing dot" do
    expect(parse("Lee, H.T.B, Chau, Y.C., Lam, H.S.B."))
      .to eq [["Lee", ["H.T.B"]], ["Chau", ["Y.C."]], ["Lam", ["H.S.B."]]]
  end

  it "joins a broken hyphen before a capital" do
    expect(parse("Corell, D.D., Dam- Hansen, C., Thorseth, A."))
      .to eq [["Corell", ["D.D."]], ["Dam-Hansen", ["C."]], ["Thorseth", ["A."]]]
  end

  it "keeps Chinese-style name order whole" do
    expect(parse("Pan Jiangen, Li Qian, Li Xiaoni"))
      .to eq [["Pan Jiangen"], ["Li Qian"], ["Li Xiaoni"]]
  end

  it "splits on a conjunction before the final author" do
    expect(parse("Ruggaber, B., Vollrath, T., Krüger, U., Blattner, P. and Gerloff, T."))
      .to eq [
        ["Ruggaber", ["B."]],
        ["Vollrath", ["T."]],
        ["Krüger", ["U."]],
        ["Blattner", ["P."]],
        ["Gerloff", ["T."]],
      ]
  end
end
