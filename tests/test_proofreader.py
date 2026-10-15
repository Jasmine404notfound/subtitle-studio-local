import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("proofread", Path(__file__).resolve().parents[1] / "Sources" / "SubtitleStudio" / "Resources" / "proofread.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ProtectionTests(unittest.TestCase):
    def test_allowed_context_edits(self):
        self.assertTrue(module.allowed_edit("他做的很好", "她做得很好", True, True))
        self.assertTrue(module.allowed_edit("他认真得分析消费者的需求", "她认真地分析消费者的需求", True, True, "消费者"))
        self.assertTrue(module.allowed_edit("公司18年成立", "公司2018年成立", True, True))
        self.assertTrue(module.allowed_edit("99年到18年", "1999年到2018年", True, True))

    def test_reject_duration_and_other_changes(self):
        for before, after in [("工作18年", "工作2018年"), ("过去18年", "过去2018年"),
                              ("18年时间", "2018年时间"), ("2018年", "1918年"),
                              ("他做得很好", "她做得特别好"), ("成本18元", "成本2018元"),
                              ("他来了。", "她来了！")]:
            self.assertFalse(module.allowed_edit(before, after, True, True), (before, after))

    def test_fixed_words_and_names(self):
        self.assertFalse(module.allowed_edit("我的目的", "我的目地", True, True))
        self.assertFalse(module.allowed_edit("觉得值得", "觉得值的", True, True))
        self.assertFalse(module.allowed_edit("彼得喜欢她", "彼的喜欢她", True, True, "彼得"))
        self.assertTrue(module.allowed_edit("得到他帮助", "得到她帮助", True, True))

    def test_settings_are_respected(self):
        self.assertFalse(module.allowed_edit("他做的好", "她做得好", True, False))
        self.assertFalse(module.allowed_edit("18年成立", "2018年成立", False, True))

    def test_translation_insertions(self):
        text = "我们讨论 product market fit 和增长。"
        items = [{"source": "product market fit", "translation": "产品与市场匹配"}]
        self.assertEqual(module.insert_translations(text, items), "我们讨论 product market fit（产品与市场匹配） 和增长。")
        self.assertEqual(module.insert_translations("product market fit（已有翻译）", items), "product market fit（已有翻译）")
        self.assertEqual(module.insert_translations(text, [{"source": "market", "translation": "恶意\n换行"}]), text)
        self.assertEqual(module.insert_translations("marketing", [{"source": "market", "translation": "市场"}]), "marketing")
        self.assertEqual(module.insert_translations(text, [{"source": "不存在", "translation": "伪造"}]), text)

    def test_vocabulary_names_are_not_translated(self):
        self.assertTrue(module.is_vocabulary_name("baby care", "海龟爸爸，Babycare，ROI"))
        self.assertTrue(module.is_vocabulary_name("BABYCARE", "Babycare"))
        self.assertFalse(module.is_vocabulary_name("babycareful", "Babycare"))

    def test_parser(self):
        self.assertEqual(module.parse_json('```json\n{"changes":[]}\n```'), {"changes": []})
        with self.assertRaises(ValueError):
            module.parse_json("错误文本")


if __name__ == "__main__":
    unittest.main()
