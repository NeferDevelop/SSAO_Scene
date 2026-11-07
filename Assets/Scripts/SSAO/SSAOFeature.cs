using System;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;
using UnityEngine.Rendering.RenderGraphModule.Util;
using UnityEngine.Rendering.Universal;

namespace SSAO
{
    public sealed class SSAOFeature : ScriptableRendererFeature
    {
        [Serializable]
        public sealed class Settings
        {
            public Shader shader;
            [Min(0f)] public float radius = 0.5f;
            [Min(0)] public int sampleCount = 16;
            [Min(0f)] public float intensity = 1f;
            public DisplayMode displayMode = DisplayMode.Composite;
            public bool enabled = true;
        }

        public enum DisplayMode
        {
            Composite,
            AmbientOcclusion
        }

        public Settings settings = new Settings();

        static SSAOFeature activeFeature;
        Material material;
        SSAOPass pass;

        public override void Create()
        {
            if (settings.shader == null)
                settings.shader = Shader.Find("Hidden/SSAO/Template");

            CoreUtils.Destroy(material);
            material = settings.shader == null ? null : CoreUtils.CreateEngineMaterial(settings.shader);
            pass = material == null ? null : new SSAOPass(material, settings);
            activeFeature = this;
        }

        public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
        {
            if (pass == null || !settings.enabled || renderingData.cameraData.isPreviewCamera)
                return;

            pass.renderPassEvent = RenderPassEvent.BeforeRenderingPostProcessing;
            pass.ConfigureInput(ScriptableRenderPassInput.Depth | ScriptableRenderPassInput.Normal);
            renderer.EnqueuePass(pass);
        }

        protected override void Dispose(bool disposing)
        {
            if (activeFeature == this)
                activeFeature = null;

            CoreUtils.Destroy(material);
        }

        // Optional runtime API for a component or input system; no scene object is required.
        public static bool TrySetRuntimeSettings(
            bool enabled,
            float radius,
            int sampleCount,
            float intensity,
            DisplayMode displayMode)
        {
            if (activeFeature == null)
                return false;

            activeFeature.settings.enabled = enabled;
            activeFeature.settings.radius = Mathf.Max(0f, radius);
            activeFeature.settings.sampleCount = Mathf.Max(0, sampleCount);
            activeFeature.settings.intensity = Mathf.Max(0f, intensity);
            activeFeature.settings.displayMode = displayMode;
            return true;
        }

        sealed class SSAOPass : ScriptableRenderPass
        {
            readonly Material material;
            readonly Settings settings;

            public SSAOPass(Material material, Settings settings)
            {
                this.material = material;
                this.settings = settings;
                ConfigureInput(ScriptableRenderPassInput.Depth | ScriptableRenderPassInput.Normal);
            }

            public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer frameData)
            {
                var resourceData = frameData.Get<UniversalResourceData>();
                var source = resourceData.activeColorTexture;
                var descriptor = source.GetDescriptor(renderGraph);
                descriptor.msaaSamples = MSAASamples.None;
                descriptor.clearBuffer = false;
                descriptor.name = "SSAO Temporary Color";
                var temporary = renderGraph.CreateTexture(descriptor);

                material.SetFloat("_SSAO_Radius", settings.radius);
                material.SetFloat("_SSAO_SampleCount", settings.sampleCount);
                material.SetFloat("_SSAO_Intensity", settings.intensity);
                material.SetFloat("_SSAO_DisplayMode", (float)settings.displayMode);

                renderGraph.AddBlitPass(
                    new RenderGraphUtils.BlitMaterialParameters(source, temporary, material, 0),
                    "SSAO Template");
                renderGraph.AddBlitPass(
                    temporary,
                    source,
                    Vector2.one,
                    Vector2.zero,
                    passName: "SSAO Template Copy Back");
            }

        }
    }
}
