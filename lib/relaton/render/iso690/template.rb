# frozen_string_literal: true

module Relaton
  module Render
    module Iso690
      # A citation template as declared in a style instance: literal text
      # interleaved with {{slot}} placeholders resolved against the ISO 690
      # data element inventory. A leading literal attaches to the first
      # slot, and a literal between two slots to the preceding one, so an
      # absent field never orphans punctuation around it. The last rendered
      # slot gives up its trailing literal in favour of the template
      # terminator, appended once when any field rendered and the output
      # does not already end with it.
      class Template
        SLOT = /\{\{\s*([\w-]+)\s*\}\}/.freeze

        Field = Struct.new(:present?, :text)

        def initialize(source)
          @chunks = []
          @terminator = ""
          scan(source.to_s)
        end

        # The short cite renders the reference with the first-biblio
        # marker appended to its first component: isodoc's styled
        # references (eref2linkshort) split there (the 1.x
        # fmt-first-biblio-delim)
        def evaluate_short(fields, delim)
          present = present_indices(fields)
          return "" if present.empty?

          # The split marker follows the leading run of present slots
          # (the 1.x first SEGMENT: "{{creator}}{{role}}" splits after
          # the role), before the first literal that follows it
          lead_slots = []
          @chunks.each_with_index do |(kind, _value), i|
            break if kind != :slot || !present.include?(i)

            lead_slots << i
          end
          split_at = lead_slots.last ? lead_slots.last + 1 : nil

          out = +""
          @chunks.each_with_index do |(kind, value), i|
            text =
              case kind
              when :slot
                field = fields[normalise(value)]
                next unless field&.present?

                field.text
              else
                next unless bridged?(i, present)

                value
              end
            if split_at == i
              out << fieldless(lead_slots, fields) if false
              out << delim.to_s
              split_at = nil
            end
            out << text unless text.nil?
          end
          out << delim.to_s if split_at == @chunks.length
          terminate(out).rstrip
        end

        # 1.x segment-join semantics: present elements joined with the
        # template's separators — a literal renders only when it
        # separates (a run of absent elements between) two present
        # elements; leading and trailing literals drop with the
        # elements they would have attached to
        def evaluate(fields)
          present = present_indices(fields)
          return "" if present.empty?

          out = +"".dup
          # Parenthetical groups balance on the template's literal
          # parens alone: data text (a series run "(N.S.)", a host
          # creator's closing paren) carries parens of its own that
          # are no part of the template's group structure
          paren_balance = 0
          @chunks.each_with_index do |(kind, value), i|
            if kind == :slot
              field = fields[normalise(value)]
              out << field.text if field&.present?
            elsif value.to_s.match?(/\A[）)]/)
              # Symmetric close: with no pending open the close-paren
              # drops, and any trailing punctuation bridges normally
              closes = value.to_s[/\A[）)]+/]
              emitted = [paren_balance, closes.size].min
              if emitted.positive?
                out << closes[0, emitted] +
                  value.to_s[closes.size..].to_s
                paren_balance -= emitted
              else
                rest = value.to_s.sub(/\A[）)]+/, "")
                # the trailing separator of a dropped group bridges as
                # though the group were never there
                if !rest.empty? && present.any? { |j| j > i } &&
                   group_gap?(i, present)
                  out << rest
                end
              end
            elsif value.to_s.match?(/[（(]\z/)
              # A literal opening a parenthetical group ("({{series}})",
              # "。（{{series}}）") attaches its paren to the slot it
              # opens — the pair drops with an absent element, while
              # any leading punctuation bridges normally
              lead, paren = value.to_s.match(/\A(.*)([（(])\z/).captures
              out << lead if bridged_text?(i, lead, present)
              if present.include?(i + 1)
                out << paren
                paren_balance += 1
              end
            elsif bridged?(i, present) ||
                  (value.include?("<") && present.any? { |j| j < i })
              # markup attaches to the element it closes
              out << value
            elsif close_pending_paren?(out, value)
              out << value
            end
          end
          terminate(out).rstrip
        end

        private

        def scan(source)
          rest = source
          while (slot = SLOT.match(rest))
            @chunks << [:text, rest[0...slot.begin(0)]] if
              slot.begin(0).positive?
            @chunks << [:slot, slot[1]]
            rest = rest[slot.end(0)..]
          end
          @terminator = rest
        end

        def present_indices(fields)
          @chunks.each_index.select do |i|
            kind, value = @chunks[i]
            next false unless kind == :slot

            field = fields[normalise(value)]
            !field.nil? && field.present?
          end
        end

        # The texts between this close and the last present slot are
        # all parenthetical-group parts (each dropped or partial)
        def group_gap?(index, present)
          left = present.select { |i| i < index }.max
          @chunks[(left + 1)...index].all? do |(_, text)|
            text.to_s.match?(/\A[）)]|[（(]\z/)
          end
        end

        # The leading punctuation of a paren-opening literal bridges
        # per the segment-join rule (a bare paren has no lead)
        def bridged_text?(index, lead, present)
          return true if lead.empty?

          first_slot = @chunks.index { |(kind, _)| kind == :slot }
          return present.include?(first_slot) if index < first_slot

          left = present.select { |i| i < index }.max
          left && present.any? { |i| i > index } &&
            !@chunks[(left + 1)...index].any? do |(kind, _)|
              kind == :text
            end
        end

        # A literal is the trailing separator of the element that
        # precedes it: it renders when that element renders and a
        # later element renders, and it is the FIRST literal of its
        # gap (the 1.x segment join — absent elements between two
        # present ones leave the single separator that follows the
        # earlier present element; an absent slot directly before a
        # present one, as "{{date}}{{disambiguator}}, {{access}}",
        # does not swallow it). A leading literal (no slot precedes
        # it) attaches to the first slot, emitting only when that
        # slot is present.
        def bridged?(index, present)
          first_slot = @chunks.index { |(kind, _)| kind == :slot }
          return present.include?(first_slot) if index < first_slot

          left = present.select { |i| i < index }.max
          left && present.any? { |i| i > index } &&
            !@chunks[(left + 1)...index].any? do |(kind, _)|
              kind == :text
            end
        end

        # A template's paired literal ("({{production}})") closes even
        # when nothing follows the present element it wraps. Fullwidth
        # parens (CJK) pair the same way
        def close_pending_paren?(out, value)
          return false unless value.start_with?(")", "\uFF09")

          opens = out.count("(") + out.count("\uFF08")
          closes = out.count(")") + out.count("\uFF09")
          opens > closes
        end

        def terminate(body)
          # 1.x punctuation cleanup: a sentence period before a spaced
          # comma yields to the comma (", 2013" over ". , 2013"; an
          # initials period before a comma ("P.,") stands, being
          # unspaced), and stacked separators around absent elements
          # collapse into one (". : ." into ". "); an empty pair left
          # by an absent element drops
          body = body.gsub(/:\s*\.\s*/, ": ")
          body = body.gsub(/\.\s+,/, ",")
          body = body.gsub(/(?:[.,:;]\s+)+[.,:;]/, ". ")
          body = body.gsub(/\.\s*\./, ". ")
          body = body.gsub(/:\s*\.\s*/, ": ")
          body = body.gsub(/\(\s*\)/, "")
          body = body.gsub(/ +/, " ").gsub(" ,", ",")
          terminator = unbalanced_close(body, @terminator)
          return body if terminator.strip.empty?
          if terminator !~ /[<\w]/ && body.rstrip.end_with?(terminator.strip)
            return body
          end

          "#{body}#{terminator}"
        end

        # The terminator's closing parens stand only when the body
        # opened them (their "(" died with an absent element)
        def unbalanced_close(body, terminator)
          return terminator unless terminator.start_with?(")")

          open = body.count("(") - body.count(")")
          return terminator.sub(/\A\)+/) { |closes| closes[0, open] } if
            open.positive?

          terminator.sub(/\A\)+/, "")
        end

        def normalise(slot)
          slot.to_s.delete("_").downcase
        end
      end
    end
  end
end
