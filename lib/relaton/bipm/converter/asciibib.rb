module Relaton
  module Bipm
    module Converter
      module Asciibib
        def self.from_item(item)
          ToAsciibib.new(item).transform
        end

        class ToAsciibib < Bib::Converter::Asciibib::ToAsciibib
          def transform
            out = super
            return out unless @item.ext

            out << render_comment_period
            out << render_si_aspect
            out << render_meeting_note
            out
          end

          private

          def render_doctype
            return "" unless @item.ext&.doctype

            "doctype.type:: #{@item.ext.doctype.content}\n"
          end

          def render_structuredidentifiers
            return "" unless @item.ext&.structuredidentifier

            si = @item.ext.structuredidentifier
            pref = "structuredidentifier"
            out = "#{pref}.docnumber:: #{si.docnumber}\n"
            out << "#{pref}.part:: #{si.part}\n" if si.part
            out << "#{pref}.appendix:: #{si.appendix}\n" if si.appendix
            out
          end

          def render_comment_period
            return "" unless @item.ext.comment_period

            cp = @item.ext.comment_period
            out = ""
            out << "commentperiod.from:: #{cp.from}\n" if cp.from
            out << "commentperiod.to:: #{cp.to}\n" if cp.to
            out
          end

          def render_si_aspect
            return "" unless @item.ext.si_aspect

            "si_aspect:: #{@item.ext.si_aspect}\n"
          end

          def render_meeting_note
            return "" unless @item.ext.meeting_note

            "meeting_note:: #{@item.ext.meeting_note}\n"
          end
        end
      end
    end
  end
end
