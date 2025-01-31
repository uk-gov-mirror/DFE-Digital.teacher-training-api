require "rails_helper.rb"

describe WordsCountValidator do
  maximum = 10

  before do
    stub_const("Validatable", Class.new).class_eval do
      include ActiveModel::Validations
      attr_accessor :some_words
      validates :some_words, words_count: { maximum: maximum }
    end
  end

  let(:model) {
    model = Validatable.new
    model.some_words = some_words_field
    model
  }

  let(:expected_errors) { ["^Reduce the word count for some words"] }

  subject! {
    model.valid?
  }

  context "with max valid number of words" do
    let(:some_words_field) { (%w[word] * maximum).join(" ") }
    it { should be true }
  end

  context "with no words" do
    let(:some_words_field) { "" }
    it { should be true }
  end

  context "with nil words" do
    let(:some_words_field) { nil }
    it { should be true }
  end

  context "with invalid number of words" do
    let(:some_words_field) { (%w[word] * maximum).join(" ") + " popped" }

    it { should be false }
    it "adds an error" do
      expect(model.errors[:some_words]).to match_array expected_errors
    end
  end

  context "with newlines" do
    let(:some_words_field) { (%w[word] * maximum).join("\n") + " popped" }

    it { should be false }
    it "adds an error" do
      expect(model.errors[:some_words]).to match_array expected_errors
    end
  end

  context "with non-words such as markdown" do
    let(:some_words_field) { (%w[word] * maximum).join(" ") + " *" }

    it { should be false }
    it "adds an error" do
      expect(model.errors[:some_words]).to match_array expected_errors
    end
  end
end
