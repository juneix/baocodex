package local.baocode.mobile

data class ApkIdentity(
    val packageName: String,
    val version: String?,
    val build: Long,
    val signers: Set<String>,
)

object UpdatePolicy {
    fun isAllowed(installed: ApkIdentity, candidate: ApkIdentity, expectedVersion: String): Boolean =
        installed.packageName == candidate.packageName &&
            candidate.version == expectedVersion &&
            candidate.build > installed.build &&
            installed.signers.isNotEmpty() &&
            installed.signers == candidate.signers
}
