Shader "Hidden/SSAO/Template"
{
    SubShader
    {
        Tags { "RenderPipeline" = "UniversalPipeline" }

        Pass
        {
            Name "SSAO Template"
            ZTest Always
            ZWrite Off
            Cull Off

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareNormalsTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/GlobalSamplers.hlsl"

            TEXTURE2D_X(_BlitTexture);

            CBUFFER_START(UnityPerMaterial)
                float _SSAO_Radius;
                float _SSAO_SampleCount;
                float _SSAO_Intensity;
                float _SSAO_DisplayMode;
            CBUFFER_END

            struct Attributes
            {
                uint vertexID : SV_VertexID;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            Varyings Vert(Attributes input)
            {
                Varyings output;
                output.positionCS = GetFullScreenTriangleVertexPosition(input.vertexID);
                output.uv = GetFullScreenTriangleTexCoord(input.vertexID);
                return output;
            }

            float3 ReconstructWorldPosition(float2 uv, float deviceDepth)
            {
                return ComputeWorldSpacePosition(uv, deviceDepth, UNITY_MATRIX_I_VP);
            }



            float EvaluateAO(float2 uv, float deviceDepth, float3 normalWS, float3 positionWS)
            {
                // Линейная глубина текущего пикселя в координатах камеры.
                float centerEyeDepth = LinearEyeDepth(deviceDepth, _ZBufferParams);

                if (centerEyeDepth >= _ProjectionParams.z * 0.999)
                    return 1.0;

                // Минимальное расстояние, в пределах которого ищется перекрывающая геометрия.
                float radius = max(_SSAO_Radius, 0.0001);

                // Количество направлений, используемых для оценки затенения.
                int sampleCount = clamp((int)round(_SSAO_SampleCount), 1, 64);

                // Нормализованная нормаль поверхности.
                normalWS = normalize(normalWS);

                // Вспомогательная ось для построения локальной системы координат.
                float3 helper = abs(normalWS.z) < 0.999
                    ? float3(0.0, 0.0, 1.0)
                    : float3(0.0, 1.0, 0.0);

                // Ось, перпендикулярная нормали и вспомогательной оси.
                float3 tangent = normalize(cross(helper, normalWS));

                // Вторая ось касательной плоскости, перпендикулярная нормали и tangent.
                float3 bitangent = cross(normalWS, tangent);

                // Координаты текущего пикселя в экранном пространстве.
                float2 pixel = uv * _ScreenParams.xy;

                // Псевдослучайное значение, зависящее от положения пикселя.
                float randomValue = frac(
                    sin(dot(pixel, float2(12.9898, 78.233))) * 43758.5453
                );

                // Случайный угол поворота направлений выборки вокруг нормали.
                float rotation = randomValue * 6.28318530718;

                // Синус угла поворота для вращения направлений в касательной плоскости.
                float sinRotation = sin(rotation);

                // Косинус угла поворота для вращения направлений в касательной плоскости.
                float cosRotation = cos(rotation);

                // Минимальная разница глубин, необходимая для фиксации перекрытия.
                float bias = 0.005;

                // Суммарное количество обнаруженных перекрытий.
                float occlusion = 0.0;

                // Выполняем заданное количество выборок в полусфере над поверхностью.
                [loop]
                for (int i = 0; i < sampleCount; i++)
                {
                    // Псевдослучайное начальное значение для текущей выборки.
                    float sampleSeed = randomValue + i * 12.9898;

                    // Дополнительное смещение, позволяющее разнообразить положение выборок.
                    float jitter = frac(
                        sin(sampleSeed * 78.233) * 43758.5453
                    );

                    // Нормализованное положение текущей выборки в последовательности.
                    float u = (i + jitter) / sampleCount;

                    // Угол направления выборки в полусфере.
                    float phi = 6.28318530718 * frac(i * 0.61803398875 + randomValue);

                    // Синус полярного угла, используемый для построения направления.
                    float sinTheta = sqrt(u);

                    // Косинус полярного угла, задающий составляющую вдоль нормали.
                    float cosTheta = sqrt(1.0 - u);

                    // Координата направления выборки по первой касательной оси.
                    float localX = sinTheta * cos(phi);

                    // Координата направления выборки по второй касательной оси.
                    float localY = sinTheta * sin(phi);

                    // Координата направления выборки вдоль нормали поверхности.
                    float localZ = cosTheta;

                    // Первая координата направления после случайного поворота.
                    float rotatedX = localX * cosRotation - localY * sinRotation;

                    // Вторая координата направления после случайного поворота.
                    float rotatedY = localX * sinRotation + localY * cosRotation;

                    // Направление выборки в мировой системе координат.
                    float3 sampleDirection =
                        tangent * rotatedX +
                        bitangent * rotatedY +
                        normalWS * localZ;

                    sampleDirection = normalize(sampleDirection);

                    // Нормализованное расстояние текущей выборки внутри радиуса AO.
                    float t = (i + 0.5) / sampleCount;

                    // Фактическое расстояние от поверхности до точки выборки.
                    float sampleDistance = radius * lerp(0.15, 1.0, t * t);

                    // Положение предполагаемой точки выборки в мировых координатах.
                    float3 samplePositionWS = positionWS + sampleDirection * sampleDistance;

                    // Координаты точки выборки после преобразования в пространство отсечения.
                    float4 sampleClip = TransformWorldToHClip(samplePositionWS);

                    if (sampleClip.w <= 0.0001)
                        continue;

                    // Координаты точки выборки на экране с учётом перспективной проекции.
                    float4 projected = ComputeScreenPos(sampleClip);

                    // Экранные UV-координаты точки выборки.
                    float2 sampleUV = projected.xy / projected.w;

                    // Пропускаем выборки, которые находятся за пределами экрана.
                    if (sampleUV.x < 0.0 || sampleUV.x > 1.0 ||
                        sampleUV.y < 0.0 || sampleUV.y > 1.0)
                    {
                        continue;
                    }

                    // Значение глубины сцены в точке выборки в исходном формате.
                    float sampleDeviceDepth = SampleSceneDepth(sampleUV);

                    // Линейная глубина видимой геометрии в точке выборки.
                    float sceneEyeDepth = LinearEyeDepth(sampleDeviceDepth, _ZBufferParams);

                    // Если в экранной точке нет геометрии, выборка пропускается.
                    if (sceneEyeDepth >= _ProjectionParams.z * 0.999)
                        continue;

                    // Линейная глубина предполагаемой точки выборки относительно камеры.
                    float sampleEyeDepth =
                        -TransformWorldToView(samplePositionWS).z;

                    // Разница между глубиной предполагаемой точки и видимой геометрии.
                    float depthDifference = sampleEyeDepth - sceneEyeDepth;

                    // Результат проверки перекрытия: 1 — перекрытие обнаружено, 0 — нет.
                    float isOccluded = step(bias, depthDifference);

                    occlusion += isOccluded;
                }

                // Итоговая доля незатенённых направлений.
                float ao = 1.0 - occlusion / sampleCount;

                // Ограниченное значение AO в диапазоне от 0 до 1.
                return saturate(ao);
            }



            half4 Frag(Varyings input) : SV_Target
            {
                float4 source = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, input.uv);
                float deviceDepth = SampleSceneDepth(input.uv);
                float3 normalWS = SampleSceneNormals(input.uv);
                float3 positionWS = ReconstructWorldPosition(input.uv, deviceDepth);
                float ao = EvaluateAO(input.uv, deviceDepth, normalWS, positionWS);

                if (_SSAO_DisplayMode > 0.5)
                    return half4(ao, ao, ao, 1.0);

                float effect = lerp(1.0, ao, saturate(_SSAO_Intensity));
                return half4(source.rgb * effect, source.a);
            }
            ENDHLSL
        }
    }
}
