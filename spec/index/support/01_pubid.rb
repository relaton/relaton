require "lutaml/model"

# Lightweight stand-in for a flavor Pubid identifier, used to exercise
# the pubid-aware code paths in relaton-index without depending on a real
# flavor's full Lutaml shape. Pubid 2.x has no Pubid::Core::Identifier;
# define just the surface the relaton-index specs touch.
class TestIdentifier < Lutaml::Model::Serializable
  attribute :publisher, :string
  attribute :number, :string
  attribute :edition, :string

  def self.create(**attrs)
    attrs[:number] = attrs[:number].to_s if attrs.key?(:number)
    new(**attrs)
  end

  # Pubid identifiers always answer `#root`: it walks a supplement's `.base`
  # chain to the origin document and returns self for a base document. The
  # index narrowing/sort key is `id.root.number.to_s`. Default to self; a spec
  # can assign an explicit root to model a supplement whose origin document has
  # a different number.
  attr_writer :root

  def root
    @root || self
  end

  def ==(other)
    return false unless other.is_a?(TestIdentifier)

    publisher == other.publisher && number == other.number &&
      edition == other.edition
  end

  # `Pubid::SubsetMatch` in miniature: the receiver is the reference, and a
  # component it leaves nil matches any value. `Relaton::Index::Type#search`
  # calls this when it gets no block, so the stub has to answer it.
  def ===(other)
    return false unless other.is_a?(TestIdentifier)

    %i[publisher number edition].all? do |attr|
      mine = public_send(attr)
      mine.nil? || mine == other.public_send(attr)
    end
  end

  alias eql? ==

  def hash
    [self.class, publisher, number].hash
  end

  # String-search code paths in Relaton::Index::Type rely on to_s.
  def to_s
    [publisher, number, edition].compact.join(" ")
  end
end
