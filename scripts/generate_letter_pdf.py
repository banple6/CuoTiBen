#!/usr/bin/env python3
"""Generate a paginated Chinese PDF from the letter's Markdown source."""

from pathlib import Path
from xml.sax.saxutils import escape

from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_JUSTIFY, TA_RIGHT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.cidfonts import UnicodeCIDFont
from reportlab.platypus import BaseDocTemplate, Frame, PageTemplate, Paragraph, Spacer


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "deliverables" / "给圆圆的一封信.md"
OUTPUT = ROOT / "deliverables" / "写给圆圆的一封信.pdf"


def add_page_number(canvas, doc):
    canvas.saveState()
    canvas.setStrokeColor(colors.HexColor("#D9C2B0"))
    canvas.line(25 * mm, 15 * mm, A4[0] - 25 * mm, 15 * mm)
    canvas.setFont("STSong-Light", 8)
    canvas.setFillColor(colors.HexColor("#8A6D5A"))
    canvas.drawCentredString(A4[0] / 2, 9.5 * mm, f"— {doc.page} —")
    canvas.restoreState()


def main():
    pdfmetrics.registerFont(UnicodeCIDFont("STSong-Light"))
    styles = getSampleStyleSheet()
    title = ParagraphStyle("LetterTitle", parent=styles["Title"], fontName="STSong-Light", fontSize=25,
                           leading=35, alignment=TA_CENTER, textColor=colors.HexColor("#5B3D2E"), spaceAfter=22 * mm)
    salutation = ParagraphStyle("Salutation", parent=styles["BodyText"], fontName="STSong-Light", fontSize=14,
                                leading=24, textColor=colors.HexColor("#332A25"), spaceAfter=8 * mm)
    body = ParagraphStyle("LetterBody", parent=styles["BodyText"], fontName="STSong-Light", fontSize=11.5,
                          leading=23, alignment=TA_JUSTIFY, firstLineIndent=23, textColor=colors.HexColor("#332A25"),
                          spaceAfter=5 * mm)
    closing = ParagraphStyle("Closing", parent=body, alignment=TA_RIGHT, firstLineIndent=0, spaceBefore=8 * mm)

    document = BaseDocTemplate(str(OUTPUT), pagesize=A4, leftMargin=25 * mm, rightMargin=25 * mm,
                               topMargin=24 * mm, bottomMargin=24 * mm, title="写给圆圆的一封信", author="小雨")
    frame = Frame(document.leftMargin, document.bottomMargin, document.width, document.height, id="letter")
    document.addPageTemplates(PageTemplate(id="Letter", frames=frame, onPage=add_page_number))

    story = [Spacer(1, 13 * mm), Paragraph("写给圆圆的一封信", title)]
    paragraphs = SOURCE.read_text(encoding="utf-8").split("\n\n")
    for raw in paragraphs[1:]:
        text = raw.strip()
        if not text:
            continue
        if text.startswith('<div align="right">'):
            story.append(Paragraph(escape(text.removeprefix('<div align="right">').removesuffix("</div>")), closing))
        elif text == "圆圆：":
            story.append(Paragraph(escape(text), salutation))
        else:
            story.append(Paragraph(escape(text), body))
    document.build(story)


if __name__ == "__main__":
    main()
