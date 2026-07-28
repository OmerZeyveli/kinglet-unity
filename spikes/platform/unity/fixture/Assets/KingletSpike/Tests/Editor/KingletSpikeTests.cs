using NUnit.Framework;

namespace KingletSpike.Tests
{
    public sealed class KingletSpikeTests
    {
        [Test]
        public void ProjectMarkerMatchesPinnedFixture()
        {
            Assert.That(Probe.ProjectId, Is.EqualTo("kinglet-unity-probe"));
        }
    }
}
