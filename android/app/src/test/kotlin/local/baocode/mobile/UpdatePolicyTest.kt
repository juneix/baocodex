package local.baocode.mobile

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class UpdatePolicyTest {
    private val installed = ApkIdentity("local.ycode.mobile", "0.2.0", 34, setOf("official"))

    @Test fun `相同包名和签名的新版本可以安装`() {
        assertTrue(UpdatePolicy.isAllowed(installed,
            installed.copy(version = "0.3.0", build = 35), "0.3.0"))
    }

    @Test fun `拒绝错误包名签名版本和降级`() {
        val candidate = installed.copy(version = "0.3.0", build = 35)
        for (invalid in listOf(
            candidate.copy(packageName = "other.app"),
            candidate.copy(signers = setOf("other")),
            candidate.copy(signers = emptySet()),
            candidate.copy(version = "0.4.0"),
            candidate.copy(build = 34),
            candidate.copy(build = 1),
        )) {
            assertFalse(UpdatePolicy.isAllowed(installed, invalid, "0.3.0"))
        }
    }

    @Test fun `缺少已装应用签名时不允许安装`() {
        assertFalse(UpdatePolicy.isAllowed(installed.copy(signers = emptySet()),
            installed.copy(version = "0.3.0", build = 35), "0.3.0"))
    }
}
