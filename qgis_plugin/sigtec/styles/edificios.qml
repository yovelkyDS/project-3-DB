<!DOCTYPE qgis PUBLIC 'http://mrcc.com/qgis.dtd' 'SYSTEM'>
<qgis version="3.44.15-Solothurn" symbologyReferenceScale="-1" styleCategories="Symbology|Labeling|MapTips|Rendering" simplifyDrawingHints="1" simplifyDrawingTol="1" minScale="100000000" simplifyAlgorithm="0" simplifyMaxScale="1" maxScale="0" hasScaleBasedVisibilityFlag="0" autoRefreshMode="Disabled" labelsEnabled="1" autoRefreshTime="0" simplifyLocal="1">
  <renderer-v2 forceraster="0" referencescale="-1" enableorderby="0" type="RuleRenderer" symbollevels="0">
    <rules key="{333019ce-b219-4f81-9ca5-a705d07cd689}">
      <rule label="Edificio institucional" filter="&quot;nombre&quot; NOT LIKE '%sin nombre en OSM%' AND NOT (&quot;nombre&quot; LIKE '%UTN%')" symbol="0" key="{2c5090f8-33a0-4ae4-bf45-ed2d38744639}"/>
      <rule label="Edificio de la UTN (sede anfitriona)" filter="&quot;nombre&quot; LIKE '%UTN%'" symbol="1" key="{8ee81a6d-f84e-4698-a4ef-588a43581ae2}"/>
      <rule label="Edificio sin nombre registrado" filter="NOT (&quot;nombre&quot; NOT LIKE '%sin nombre en OSM%')" symbol="2" key="{19602818-fbee-4bb9-a8ea-0e5e486ec659}"/>
    </rules>
    <symbols>
      <symbol force_rhr="0" type="fill" alpha="1" is_animated="0" name="0" clip_to_extent="1" frame_rate="10">
        <data_defined_properties>
          <Option type="Map">
            <Option type="QString" name="name" value=""/>
            <Option name="properties"/>
            <Option type="QString" name="type" value="collection"/>
          </Option>
        </data_defined_properties>
        <layer class="SimpleFill" pass="0" enabled="1" id="{73e2ccbf-643b-429c-94b6-227d9a2ab5bb}" locked="0">
          <Option type="Map">
            <Option type="QString" name="border_width_map_unit_scale" value="3x:0,0,0,0,0,0"/>
            <Option type="QString" name="color" value="27,39,51,70,rgb:0.1058824,0.1529412,0.2,0.2745098"/>
            <Option type="QString" name="joinstyle" value="round"/>
            <Option type="QString" name="offset" value="0.34999999999999998,0.34999999999999998"/>
            <Option type="QString" name="offset_map_unit_scale" value="3x:0,0,0,0,0,0"/>
            <Option type="QString" name="offset_unit" value="MM"/>
            <Option type="QString" name="outline_color" value="27,39,51,255,rgb:0.1058824,0.1529412,0.2,1"/>
            <Option type="QString" name="outline_style" value="no"/>
            <Option type="QString" name="outline_width" value="0"/>
            <Option type="QString" name="outline_width_unit" value="MM"/>
            <Option type="QString" name="style" value="solid"/>
          </Option>
          <data_defined_properties>
            <Option type="Map">
              <Option type="QString" name="name" value=""/>
              <Option name="properties"/>
              <Option type="QString" name="type" value="collection"/>
            </Option>
          </data_defined_properties>
        </layer>
        <layer class="SimpleFill" pass="0" enabled="1" id="{f7925e14-2ce9-4609-982a-4fac35fdd7a7}" locked="0">
          <Option type="Map">
            <Option type="QString" name="border_width_map_unit_scale" value="3x:0,0,0,0,0,0"/>
            <Option type="QString" name="color" value="185,211,234,235,rgb:0.7254902,0.827451,0.9176471,0.9215686"/>
            <Option type="QString" name="joinstyle" value="round"/>
            <Option type="QString" name="offset" value="0,0"/>
            <Option type="QString" name="offset_map_unit_scale" value="3x:0,0,0,0,0,0"/>
            <Option type="QString" name="offset_unit" value="MM"/>
            <Option type="QString" name="outline_color" value="0,59,115,255,rgb:0,0.2313725,0.4509804,1"/>
            <Option type="QString" name="outline_style" value="solid"/>
            <Option type="QString" name="outline_width" value="0.45"/>
            <Option type="QString" name="outline_width_unit" value="MM"/>
            <Option type="QString" name="style" value="solid"/>
          </Option>
          <data_defined_properties>
            <Option type="Map">
              <Option type="QString" name="name" value=""/>
              <Option name="properties"/>
              <Option type="QString" name="type" value="collection"/>
            </Option>
          </data_defined_properties>
        </layer>
      </symbol>
      <symbol force_rhr="0" type="fill" alpha="1" is_animated="0" name="1" clip_to_extent="1" frame_rate="10">
        <data_defined_properties>
          <Option type="Map">
            <Option type="QString" name="name" value=""/>
            <Option name="properties"/>
            <Option type="QString" name="type" value="collection"/>
          </Option>
        </data_defined_properties>
        <layer class="SimpleFill" pass="0" enabled="1" id="{fe540103-a178-4e6a-86e4-da881cdfb26d}" locked="0">
          <Option type="Map">
            <Option type="QString" name="border_width_map_unit_scale" value="3x:0,0,0,0,0,0"/>
            <Option type="QString" name="color" value="27,39,51,70,rgb:0.1058824,0.1529412,0.2,0.2745098"/>
            <Option type="QString" name="joinstyle" value="round"/>
            <Option type="QString" name="offset" value="0.34999999999999998,0.34999999999999998"/>
            <Option type="QString" name="offset_map_unit_scale" value="3x:0,0,0,0,0,0"/>
            <Option type="QString" name="offset_unit" value="MM"/>
            <Option type="QString" name="outline_color" value="27,39,51,255,rgb:0.1058824,0.1529412,0.2,1"/>
            <Option type="QString" name="outline_style" value="no"/>
            <Option type="QString" name="outline_width" value="0"/>
            <Option type="QString" name="outline_width_unit" value="MM"/>
            <Option type="QString" name="style" value="solid"/>
          </Option>
          <data_defined_properties>
            <Option type="Map">
              <Option type="QString" name="name" value=""/>
              <Option name="properties"/>
              <Option type="QString" name="type" value="collection"/>
            </Option>
          </data_defined_properties>
        </layer>
        <layer class="SimpleFill" pass="0" enabled="1" id="{a08a0bf0-a03a-4ae8-baef-110a3f89dba5}" locked="0">
          <Option type="Map">
            <Option type="QString" name="border_width_map_unit_scale" value="3x:0,0,0,0,0,0"/>
            <Option type="QString" name="color" value="228,220,203,230,rgb:0.8941176,0.8627451,0.7960784,0.9019608"/>
            <Option type="QString" name="joinstyle" value="round"/>
            <Option type="QString" name="offset" value="0,0"/>
            <Option type="QString" name="offset_map_unit_scale" value="3x:0,0,0,0,0,0"/>
            <Option type="QString" name="offset_unit" value="MM"/>
            <Option type="QString" name="outline_color" value="138,122,92,255,rgb:0.5411765,0.4784314,0.3607843,1"/>
            <Option type="QString" name="outline_style" value="solid"/>
            <Option type="QString" name="outline_width" value="0.35"/>
            <Option type="QString" name="outline_width_unit" value="MM"/>
            <Option type="QString" name="style" value="solid"/>
          </Option>
          <data_defined_properties>
            <Option type="Map">
              <Option type="QString" name="name" value=""/>
              <Option name="properties"/>
              <Option type="QString" name="type" value="collection"/>
            </Option>
          </data_defined_properties>
        </layer>
      </symbol>
      <symbol force_rhr="0" type="fill" alpha="1" is_animated="0" name="2" clip_to_extent="1" frame_rate="10">
        <data_defined_properties>
          <Option type="Map">
            <Option type="QString" name="name" value=""/>
            <Option name="properties"/>
            <Option type="QString" name="type" value="collection"/>
          </Option>
        </data_defined_properties>
        <layer class="SimpleFill" pass="0" enabled="1" id="{89f0b6e7-0e70-4d48-9de9-704f53606a94}" locked="0">
          <Option type="Map">
            <Option type="QString" name="border_width_map_unit_scale" value="3x:0,0,0,0,0,0"/>
            <Option type="QString" name="color" value="27,39,51,70,rgb:0.1058824,0.1529412,0.2,0.2745098"/>
            <Option type="QString" name="joinstyle" value="round"/>
            <Option type="QString" name="offset" value="0.34999999999999998,0.34999999999999998"/>
            <Option type="QString" name="offset_map_unit_scale" value="3x:0,0,0,0,0,0"/>
            <Option type="QString" name="offset_unit" value="MM"/>
            <Option type="QString" name="outline_color" value="27,39,51,255,rgb:0.1058824,0.1529412,0.2,1"/>
            <Option type="QString" name="outline_style" value="no"/>
            <Option type="QString" name="outline_width" value="0"/>
            <Option type="QString" name="outline_width_unit" value="MM"/>
            <Option type="QString" name="style" value="solid"/>
          </Option>
          <data_defined_properties>
            <Option type="Map">
              <Option type="QString" name="name" value=""/>
              <Option name="properties"/>
              <Option type="QString" name="type" value="collection"/>
            </Option>
          </data_defined_properties>
        </layer>
        <layer class="SimpleFill" pass="0" enabled="1" id="{f6d3f7fa-bf23-488b-af9c-dfd3227176c3}" locked="0">
          <Option type="Map">
            <Option type="QString" name="border_width_map_unit_scale" value="3x:0,0,0,0,0,0"/>
            <Option type="QString" name="color" value="221,227,234,225,rgb:0.8666667,0.8901961,0.9176471,0.8823529"/>
            <Option type="QString" name="joinstyle" value="round"/>
            <Option type="QString" name="offset" value="0,0"/>
            <Option type="QString" name="offset_map_unit_scale" value="3x:0,0,0,0,0,0"/>
            <Option type="QString" name="offset_unit" value="MM"/>
            <Option type="QString" name="outline_color" value="127,143,160,255,rgb:0.4980392,0.5607843,0.627451,1"/>
            <Option type="QString" name="outline_style" value="solid"/>
            <Option type="QString" name="outline_width" value="0.3"/>
            <Option type="QString" name="outline_width_unit" value="MM"/>
            <Option type="QString" name="style" value="solid"/>
          </Option>
          <data_defined_properties>
            <Option type="Map">
              <Option type="QString" name="name" value=""/>
              <Option name="properties"/>
              <Option type="QString" name="type" value="collection"/>
            </Option>
          </data_defined_properties>
        </layer>
      </symbol>
    </symbols>
    <data-defined-properties>
      <Option type="Map">
        <Option type="QString" name="name" value=""/>
        <Option name="properties"/>
        <Option type="QString" name="type" value="collection"/>
      </Option>
    </data-defined-properties>
  </renderer-v2>
  <selection mode="Default">
    <selectionColor invalid="1"/>
  </selection>
  <labeling type="rule-based">
    <rules key="{a3d56b67-49cd-46ac-823d-9ca3d7817bcf}">
      <rule filter="&quot;nombre&quot; NOT LIKE '%sin nombre en OSM%' AND (regexp_match(lower(&quot;nombre&quot;), '(biblioteca|auditorio|rector|administra|gimnasio|comedor|ctec|lcc|computaci|centro de las artes|casa |aulas|docencia|tec oficinas)') > 0 OR &quot;area&quot; > 1500)" key="{829f0a7f-b07e-456b-8fb7-ccd515868f80}" description="Edificios principales">
        <settings calloutType="simple">
          <text-style fontWeight="75" fontSize="8" forcedBold="0" textColor="0,59,115,255,rgb:0,0.2313725,0.4509804,1" isExpression="0" forcedItalic="0" fontSizeMapUnitScale="3x:0,0,0,0,0,0" fontUnderline="0" textOpacity="1" fontStrikeout="0" textOrientation="horizontal" fontLetterSpacing="0" blendMode="0" multilineHeightUnit="Percentage" useSubstitutions="0" fontWordSpacing="0" fontItalic="0" capitalization="0" fontKerning="1" legendString="Aa" tabStopDistanceMapUnitScale="3x:0,0,0,0,0,0" fontFamily="Arial" previewBkgrdColor="255,255,255,255,rgb:1,1,1,1" tabStopDistance="6" allowHtml="0" namedStyle="" fieldName="nombre" fontSizeUnit="Point" multilineHeight="1" tabStopDistanceUnit="Percentage">
            <families/>
            <text-buffer bufferSize="0.90000000000000002" bufferDraw="1" bufferSizeUnits="MM" bufferJoinStyle="128" bufferNoFill="1" bufferOpacity="1" bufferSizeMapUnitScale="3x:0,0,0,0,0,0" bufferBlendMode="0" bufferColor="255,255,255,235,rgb:1,1,1,0.9215686"/>
            <text-mask maskSizeUnits="MM" maskJoinStyle="128" maskType="0" maskSize2="1.5" maskSizeMapUnitScale="3x:0,0,0,0,0,0" maskOpacity="1" maskedSymbolLayers="" maskSize="1.5" maskEnabled="0"/>
            <background shapeOffsetX="0" shapeSizeUnit="MM" shapeSizeType="0" shapeJoinStyle="64" shapeOffsetY="0" shapeRadiiUnit="MM" shapeRotationType="0" shapeBorderWidthUnit="MM" shapeBlendMode="0" shapeType="0" shapeOpacity="1" shapeBorderWidth="0" shapeOffsetUnit="MM" shapeRotation="0" shapeFillColor="255,255,255,255,rgb:1,1,1,1" shapeSizeMapUnitScale="3x:0,0,0,0,0,0" shapeSizeX="0" shapeSizeY="0" shapeOffsetMapUnitScale="3x:0,0,0,0,0,0" shapeSVGFile="" shapeRadiiMapUnitScale="3x:0,0,0,0,0,0" shapeBorderWidthMapUnitScale="3x:0,0,0,0,0,0" shapeBorderColor="128,128,128,255,rgb:0.5019608,0.5019608,0.5019608,1" shapeDraw="0" shapeRadiiX="0" shapeRadiiY="0">
              <symbol force_rhr="0" type="fill" alpha="1" is_animated="0" name="fillSymbol" clip_to_extent="1" frame_rate="10">
                <data_defined_properties>
                  <Option type="Map">
                    <Option type="QString" name="name" value=""/>
                    <Option name="properties"/>
                    <Option type="QString" name="type" value="collection"/>
                  </Option>
                </data_defined_properties>
                <layer class="SimpleFill" pass="0" enabled="1" id="" locked="0">
                  <Option type="Map">
                    <Option type="QString" name="border_width_map_unit_scale" value="3x:0,0,0,0,0,0"/>
                    <Option type="QString" name="color" value="255,255,255,255,rgb:1,1,1,1"/>
                    <Option type="QString" name="joinstyle" value="bevel"/>
                    <Option type="QString" name="offset" value="0,0"/>
                    <Option type="QString" name="offset_map_unit_scale" value="3x:0,0,0,0,0,0"/>
                    <Option type="QString" name="offset_unit" value="MM"/>
                    <Option type="QString" name="outline_color" value="128,128,128,255,rgb:0.5019608,0.5019608,0.5019608,1"/>
                    <Option type="QString" name="outline_style" value="no"/>
                    <Option type="QString" name="outline_width" value="0"/>
                    <Option type="QString" name="outline_width_unit" value="MM"/>
                    <Option type="QString" name="style" value="solid"/>
                  </Option>
                  <data_defined_properties>
                    <Option type="Map">
                      <Option type="QString" name="name" value=""/>
                      <Option name="properties"/>
                      <Option type="QString" name="type" value="collection"/>
                    </Option>
                  </data_defined_properties>
                </layer>
              </symbol>
            </background>
            <shadow shadowOpacity="0.69999999999999996" shadowBlendMode="6" shadowDraw="0" shadowRadius="1.5" shadowOffsetUnit="MM" shadowOffsetMapUnitScale="3x:0,0,0,0,0,0" shadowUnder="0" shadowOffsetGlobal="1" shadowColor="0,0,0,255,rgb:0,0,0,1" shadowOffsetAngle="135" shadowOffsetDist="1" shadowRadiusMapUnitScale="3x:0,0,0,0,0,0" shadowRadiusAlphaOnly="0" shadowScale="100" shadowRadiusUnit="MM"/>
            <dd_properties>
              <Option type="Map">
                <Option type="QString" name="name" value=""/>
                <Option name="properties"/>
                <Option type="QString" name="type" value="collection"/>
              </Option>
            </dd_properties>
            <substitutions/>
          </text-style>
          <text-format multilineAlign="3" leftDirectionSymbol="&lt;" addDirectionSymbol="0" decimals="3" useMaxLineLengthForAutoWrap="1" wrapChar="" autoWrapLength="20" placeDirectionSymbol="0" reverseDirectionSymbol="0" plussign="0" formatNumbers="0" rightDirectionSymbol=">"/>
          <placement overrunDistanceMapUnitScale="3x:0,0,0,0,0,0" predefinedPositionOrder="TR,TL,BR,BL,R,L,TSR,BSR" geometryGeneratorType="PointGeometry" repeatDistance="0" maximumDistanceMapUnitScale="3x:0,0,0,0,0,0" polygonPlacementFlags="2" repeatDistanceMapUnitScale="3x:0,0,0,0,0,0" placementFlags="10" placement="1" priority="8" dist="0" layerType="UnknownGeometry" offsetType="0" quadOffset="4" xOffset="0" preserveRotation="1" distMapUnitScale="3x:0,0,0,0,0,0" yOffset="0" geometryGeneratorEnabled="0" offsetUnits="MM" repeatDistanceUnits="MM" overlapHandling="PreventOverlap" centroidInside="1" distUnits="MM" allowDegraded="0" prioritization="PreferCloser" maximumDistanceUnit="MM" maxCurvedCharAngleOut="-25" lineAnchorType="0" maxCurvedCharAngleIn="25" rotationUnit="AngleDegrees" lineAnchorClipping="0" maximumDistance="0" lineAnchorPercent="0.5" rotationAngle="0" fitInPolygonOnly="0" overrunDistance="0" geometryGenerator="" lineAnchorTextPoint="FollowPlacement" centroidWhole="1" overrunDistanceUnit="MM" labelOffsetMapUnitScale="3x:0,0,0,0,0,0"/>
          <rendering fontMaxPixelSize="10000" scaleVisibility="1" fontMinPixelSize="0" scaleMax="9000" obstacleType="1" obstacle="1" drawLabels="1" obstacleFactor="1" upsidedownLabels="0" unplacedVisibility="0" scaleMin="1" minFeatureSize="0" mergeLines="0" maxNumLabels="2000" zIndex="0" labelPerPart="0" fontLimitPixelSize="0" limitNumLabels="0"/>
          <dd_properties>
            <Option type="Map">
              <Option type="QString" name="name" value=""/>
              <Option type="Map" name="properties">
                <Option type="Map" name="OffsetXY">
                  <Option type="bool" name="active" value="true"/>
                  <Option type="QString" name="expression" value="if(regexp_match(lower(&quot;nombre&quot;), '(biblioteca|soda|comedor|restaurante|^laboratorio|auditorio|cajero|cl[ií]nica)') > 0, '0,5', '0,0')"/>
                  <Option type="int" name="type" value="3"/>
                </Option>
              </Option>
              <Option type="QString" name="type" value="collection"/>
            </Option>
          </dd_properties>
          <callout type="simple">
            <Option type="Map">
              <Option type="QString" name="anchorPoint" value="pole_of_inaccessibility"/>
              <Option type="int" name="blendMode" value="0"/>
              <Option type="Map" name="ddProperties">
                <Option type="QString" name="name" value=""/>
                <Option name="properties"/>
                <Option type="QString" name="type" value="collection"/>
              </Option>
              <Option type="bool" name="drawToAllParts" value="false"/>
              <Option type="QString" name="enabled" value="0"/>
              <Option type="QString" name="labelAnchorPoint" value="point_on_exterior"/>
              <Option type="QString" name="lineSymbol" value="&lt;symbol force_rhr=&quot;0&quot; type=&quot;line&quot; alpha=&quot;1&quot; is_animated=&quot;0&quot; name=&quot;symbol&quot; clip_to_extent=&quot;1&quot; frame_rate=&quot;10&quot;>&lt;data_defined_properties>&lt;Option type=&quot;Map&quot;>&lt;Option type=&quot;QString&quot; name=&quot;name&quot; value=&quot;&quot;/>&lt;Option name=&quot;properties&quot;/>&lt;Option type=&quot;QString&quot; name=&quot;type&quot; value=&quot;collection&quot;/>&lt;/Option>&lt;/data_defined_properties>&lt;layer class=&quot;SimpleLine&quot; pass=&quot;0&quot; enabled=&quot;1&quot; id=&quot;{9a567920-c21e-45da-ad07-099bc9be6051}&quot; locked=&quot;0&quot;>&lt;Option type=&quot;Map&quot;>&lt;Option type=&quot;QString&quot; name=&quot;align_dash_pattern&quot; value=&quot;0&quot;/>&lt;Option type=&quot;QString&quot; name=&quot;capstyle&quot; value=&quot;square&quot;/>&lt;Option type=&quot;QString&quot; name=&quot;customdash&quot; value=&quot;5;2&quot;/>&lt;Option type=&quot;QString&quot; name=&quot;customdash_map_unit_scale&quot; value=&quot;3x:0,0,0,0,0,0&quot;/>&lt;Option type=&quot;QString&quot; name=&quot;customdash_unit&quot; value=&quot;MM&quot;/>&lt;Option type=&quot;QString&quot; name=&quot;dash_pattern_offset&quot; value=&quot;0&quot;/>&lt;Option type=&quot;QString&quot; name=&quot;dash_pattern_offset_map_unit_scale&quot; value=&quot;3x:0,0,0,0,0,0&quot;/>&lt;Option type=&quot;QString&quot; name=&quot;dash_pattern_offset_unit&quot; value=&quot;MM&quot;/>&lt;Option type=&quot;QString&quot; name=&quot;draw_inside_polygon&quot; value=&quot;0&quot;/>&lt;Option type=&quot;QString&quot; name=&quot;joinstyle&quot; value=&quot;bevel&quot;/>&lt;Option type=&quot;QString&quot; name=&quot;line_color&quot; value=&quot;60,60,60,255,rgb:0.2352941,0.2352941,0.2352941,1&quot;/>&lt;Option type=&quot;QString&quot; name=&quot;line_style&quot; value=&quot;solid&quot;/>&lt;Option type=&quot;QString&quot; name=&quot;line_width&quot; value=&quot;0.3&quot;/>&lt;Option type=&quot;QString&quot; name=&quot;line_width_unit&quot; value=&quot;MM&quot;/>&lt;Option type=&quot;QString&quot; name=&quot;offset&quot; value=&quot;0&quot;/>&lt;Option type=&quot;QString&quot; name=&quot;offset_map_unit_scale&quot; value=&quot;3x:0,0,0,0,0,0&quot;/>&lt;Option type=&quot;QString&quot; name=&quot;offset_unit&quot; value=&quot;MM&quot;/>&lt;Option type=&quot;QString&quot; name=&quot;ring_filter&quot; value=&quot;0&quot;/>&lt;Option type=&quot;QString&quot; name=&quot;trim_distance_end&quot; value=&quot;0&quot;/>&lt;Option type=&quot;QString&quot; name=&quot;trim_distance_end_map_unit_scale&quot; value=&quot;3x:0,0,0,0,0,0&quot;/>&lt;Option type=&quot;QString&quot; name=&quot;trim_distance_end_unit&quot; value=&quot;MM&quot;/>&lt;Option type=&quot;QString&quot; name=&quot;trim_distance_start&quot; value=&quot;0&quot;/>&lt;Option type=&quot;QString&quot; name=&quot;trim_distance_start_map_unit_scale&quot; value=&quot;3x:0,0,0,0,0,0&quot;/>&lt;Option type=&quot;QString&quot; name=&quot;trim_distance_start_unit&quot; value=&quot;MM&quot;/>&lt;Option type=&quot;QString&quot; name=&quot;tweak_dash_pattern_on_corners&quot; value=&quot;0&quot;/>&lt;Option type=&quot;QString&quot; name=&quot;use_custom_dash&quot; value=&quot;0&quot;/>&lt;Option type=&quot;QString&quot; name=&quot;width_map_unit_scale&quot; value=&quot;3x:0,0,0,0,0,0&quot;/>&lt;/Option>&lt;data_defined_properties>&lt;Option type=&quot;Map&quot;>&lt;Option type=&quot;QString&quot; name=&quot;name&quot; value=&quot;&quot;/>&lt;Option name=&quot;properties&quot;/>&lt;Option type=&quot;QString&quot; name=&quot;type&quot; value=&quot;collection&quot;/>&lt;/Option>&lt;/data_defined_properties>&lt;/layer>&lt;/symbol>"/>
              <Option type="double" name="minLength" value="0"/>
              <Option type="QString" name="minLengthMapUnitScale" value="3x:0,0,0,0,0,0"/>
              <Option type="QString" name="minLengthUnit" value="MM"/>
              <Option type="double" name="offsetFromAnchor" value="0"/>
              <Option type="QString" name="offsetFromAnchorMapUnitScale" value="3x:0,0,0,0,0,0"/>
              <Option type="QString" name="offsetFromAnchorUnit" value="MM"/>
              <Option type="double" name="offsetFromLabel" value="0"/>
              <Option type="QString" name="offsetFromLabelMapUnitScale" value="3x:0,0,0,0,0,0"/>
              <Option type="QString" name="offsetFromLabelUnit" value="MM"/>
            </Option>
          </callout>
        </settings>
      </rule>
      <rule filter="&quot;nombre&quot; NOT LIKE '%sin nombre en OSM%' AND NOT (regexp_match(lower(&quot;nombre&quot;), '(biblioteca|auditorio|rector|administra|gimnasio|comedor|ctec|lcc|computaci|centro de las artes|casa |aulas|docencia|tec oficinas)') > 0 OR &quot;area&quot; > 1500)" key="{dbb2d5a9-eb08-4e12-96ee-dee03b44023f}" description="Demás edificios">
        <settings calloutType="simple">
          <text-style fontWeight="50" fontSize="7.5" forcedBold="0" textColor="35,70,107,255,rgb:0.1372549,0.2745098,0.4196078,1" isExpression="0" forcedItalic="0" fontSizeMapUnitScale="3x:0,0,0,0,0,0" fontUnderline="0" textOpacity="1" fontStrikeout="0" textOrientation="horizontal" fontLetterSpacing="0" blendMode="0" multilineHeightUnit="Percentage" useSubstitutions="0" fontWordSpacing="0" fontItalic="0" capitalization="0" fontKerning="1" legendString="Aa" tabStopDistanceMapUnitScale="3x:0,0,0,0,0,0" fontFamily="Arial" previewBkgrdColor="255,255,255,255,rgb:1,1,1,1" tabStopDistance="6" allowHtml="0" namedStyle="" fieldName="nombre" fontSizeUnit="Point" multilineHeight="1" tabStopDistanceUnit="Percentage">
            <families/>
            <text-buffer bufferSize="0.90000000000000002" bufferDraw="1" bufferSizeUnits="MM" bufferJoinStyle="128" bufferNoFill="1" bufferOpacity="1" bufferSizeMapUnitScale="3x:0,0,0,0,0,0" bufferBlendMode="0" bufferColor="255,255,255,235,rgb:1,1,1,0.9215686"/>
            <text-mask maskSizeUnits="MM" maskJoinStyle="128" maskType="0" maskSize2="1.5" maskSizeMapUnitScale="3x:0,0,0,0,0,0" maskOpacity="1" maskedSymbolLayers="" maskSize="1.5" maskEnabled="0"/>
            <background shapeOffsetX="0" shapeSizeUnit="MM" shapeSizeType="0" shapeJoinStyle="64" shapeOffsetY="0" shapeRadiiUnit="MM" shapeRotationType="0" shapeBorderWidthUnit="MM" shapeBlendMode="0" shapeType="0" shapeOpacity="1" shapeBorderWidth="0" shapeOffsetUnit="MM" shapeRotation="0" shapeFillColor="255,255,255,255,rgb:1,1,1,1" shapeSizeMapUnitScale="3x:0,0,0,0,0,0" shapeSizeX="0" shapeSizeY="0" shapeOffsetMapUnitScale="3x:0,0,0,0,0,0" shapeSVGFile="" shapeRadiiMapUnitScale="3x:0,0,0,0,0,0" shapeBorderWidthMapUnitScale="3x:0,0,0,0,0,0" shapeBorderColor="128,128,128,255,rgb:0.5019608,0.5019608,0.5019608,1" shapeDraw="0" shapeRadiiX="0" shapeRadiiY="0">
              <symbol force_rhr="0" type="fill" alpha="1" is_animated="0" name="fillSymbol" clip_to_extent="1" frame_rate="10">
                <data_defined_properties>
                  <Option type="Map">
                    <Option type="QString" name="name" value=""/>
                    <Option name="properties"/>
                    <Option type="QString" name="type" value="collection"/>
                  </Option>
                </data_defined_properties>
                <layer class="SimpleFill" pass="0" enabled="1" id="" locked="0">
                  <Option type="Map">
                    <Option type="QString" name="border_width_map_unit_scale" value="3x:0,0,0,0,0,0"/>
                    <Option type="QString" name="color" value="255,255,255,255,rgb:1,1,1,1"/>
                    <Option type="QString" name="joinstyle" value="bevel"/>
                    <Option type="QString" name="offset" value="0,0"/>
                    <Option type="QString" name="offset_map_unit_scale" value="3x:0,0,0,0,0,0"/>
                    <Option type="QString" name="offset_unit" value="MM"/>
                    <Option type="QString" name="outline_color" value="128,128,128,255,rgb:0.5019608,0.5019608,0.5019608,1"/>
                    <Option type="QString" name="outline_style" value="no"/>
                    <Option type="QString" name="outline_width" value="0"/>
                    <Option type="QString" name="outline_width_unit" value="MM"/>
                    <Option type="QString" name="style" value="solid"/>
                  </Option>
                  <data_defined_properties>
                    <Option type="Map">
                      <Option type="QString" name="name" value=""/>
                      <Option name="properties"/>
                      <Option type="QString" name="type" value="collection"/>
                    </Option>
                  </data_defined_properties>
                </layer>
              </symbol>
            </background>
            <shadow shadowOpacity="0.69999999999999996" shadowBlendMode="6" shadowDraw="0" shadowRadius="1.5" shadowOffsetUnit="MM" shadowOffsetMapUnitScale="3x:0,0,0,0,0,0" shadowUnder="0" shadowOffsetGlobal="1" shadowColor="0,0,0,255,rgb:0,0,0,1" shadowOffsetAngle="135" shadowOffsetDist="1" shadowRadiusMapUnitScale="3x:0,0,0,0,0,0" shadowRadiusAlphaOnly="0" shadowScale="100" shadowRadiusUnit="MM"/>
            <dd_properties>
              <Option type="Map">
                <Option type="QString" name="name" value=""/>
                <Option name="properties"/>
                <Option type="QString" name="type" value="collection"/>
              </Option>
            </dd_properties>
            <substitutions/>
          </text-style>
          <text-format multilineAlign="3" leftDirectionSymbol="&lt;" addDirectionSymbol="0" decimals="3" useMaxLineLengthForAutoWrap="1" wrapChar="" autoWrapLength="20" placeDirectionSymbol="0" reverseDirectionSymbol="0" plussign="0" formatNumbers="0" rightDirectionSymbol=">"/>
          <placement overrunDistanceMapUnitScale="3x:0,0,0,0,0,0" predefinedPositionOrder="TR,TL,BR,BL,R,L,TSR,BSR" geometryGeneratorType="PointGeometry" repeatDistance="0" maximumDistanceMapUnitScale="3x:0,0,0,0,0,0" polygonPlacementFlags="2" repeatDistanceMapUnitScale="3x:0,0,0,0,0,0" placementFlags="10" placement="1" priority="5" dist="0" layerType="UnknownGeometry" offsetType="0" quadOffset="4" xOffset="0" preserveRotation="1" distMapUnitScale="3x:0,0,0,0,0,0" yOffset="0" geometryGeneratorEnabled="0" offsetUnits="MM" repeatDistanceUnits="MM" overlapHandling="PreventOverlap" centroidInside="1" distUnits="MM" allowDegraded="0" prioritization="PreferCloser" maximumDistanceUnit="MM" maxCurvedCharAngleOut="-25" lineAnchorType="0" maxCurvedCharAngleIn="25" rotationUnit="AngleDegrees" lineAnchorClipping="0" maximumDistance="0" lineAnchorPercent="0.5" rotationAngle="0" fitInPolygonOnly="0" overrunDistance="0" geometryGenerator="" lineAnchorTextPoint="FollowPlacement" centroidWhole="1" overrunDistanceUnit="MM" labelOffsetMapUnitScale="3x:0,0,0,0,0,0"/>
          <rendering fontMaxPixelSize="10000" scaleVisibility="1" fontMinPixelSize="0" scaleMax="2200" obstacleType="1" obstacle="1" drawLabels="1" obstacleFactor="1" upsidedownLabels="0" unplacedVisibility="0" scaleMin="1" minFeatureSize="0" mergeLines="0" maxNumLabels="2000" zIndex="0" labelPerPart="0" fontLimitPixelSize="0" limitNumLabels="0"/>
          <dd_properties>
            <Option type="Map">
              <Option type="QString" name="name" value=""/>
              <Option type="Map" name="properties">
                <Option type="Map" name="OffsetXY">
                  <Option type="bool" name="active" value="true"/>
                  <Option type="QString" name="expression" value="if(regexp_match(lower(&quot;nombre&quot;), '(biblioteca|soda|comedor|restaurante|^laboratorio|auditorio|cajero|cl[ií]nica)') > 0, '0,5', '0,0')"/>
                  <Option type="int" name="type" value="3"/>
                </Option>
              </Option>
              <Option type="QString" name="type" value="collection"/>
            </Option>
          </dd_properties>
          <callout type="simple">
            <Option type="Map">
              <Option type="QString" name="anchorPoint" value="pole_of_inaccessibility"/>
              <Option type="int" name="blendMode" value="0"/>
              <Option type="Map" name="ddProperties">
                <Option type="QString" name="name" value=""/>
                <Option name="properties"/>
                <Option type="QString" name="type" value="collection"/>
              </Option>
              <Option type="bool" name="drawToAllParts" value="false"/>
              <Option type="QString" name="enabled" value="0"/>
              <Option type="QString" name="labelAnchorPoint" value="point_on_exterior"/>
              <Option type="QString" name="lineSymbol" value="&lt;symbol force_rhr=&quot;0&quot; type=&quot;line&quot; alpha=&quot;1&quot; is_animated=&quot;0&quot; name=&quot;symbol&quot; clip_to_extent=&quot;1&quot; frame_rate=&quot;10&quot;>&lt;data_defined_properties>&lt;Option type=&quot;Map&quot;>&lt;Option type=&quot;QString&quot; name=&quot;name&quot; value=&quot;&quot;/>&lt;Option name=&quot;properties&quot;/>&lt;Option type=&quot;QString&quot; name=&quot;type&quot; value=&quot;collection&quot;/>&lt;/Option>&lt;/data_defined_properties>&lt;layer class=&quot;SimpleLine&quot; pass=&quot;0&quot; enabled=&quot;1&quot; id=&quot;{3915967e-6d58-4bc2-8cd0-ff4ab5dbfe26}&quot; locked=&quot;0&quot;>&lt;Option type=&quot;Map&quot;>&lt;Option type=&quot;QString&quot; name=&quot;align_dash_pattern&quot; value=&quot;0&quot;/>&lt;Option type=&quot;QString&quot; name=&quot;capstyle&quot; value=&quot;square&quot;/>&lt;Option type=&quot;QString&quot; name=&quot;customdash&quot; value=&quot;5;2&quot;/>&lt;Option type=&quot;QString&quot; name=&quot;customdash_map_unit_scale&quot; value=&quot;3x:0,0,0,0,0,0&quot;/>&lt;Option type=&quot;QString&quot; name=&quot;customdash_unit&quot; value=&quot;MM&quot;/>&lt;Option type=&quot;QString&quot; name=&quot;dash_pattern_offset&quot; value=&quot;0&quot;/>&lt;Option type=&quot;QString&quot; name=&quot;dash_pattern_offset_map_unit_scale&quot; value=&quot;3x:0,0,0,0,0,0&quot;/>&lt;Option type=&quot;QString&quot; name=&quot;dash_pattern_offset_unit&quot; value=&quot;MM&quot;/>&lt;Option type=&quot;QString&quot; name=&quot;draw_inside_polygon&quot; value=&quot;0&quot;/>&lt;Option type=&quot;QString&quot; name=&quot;joinstyle&quot; value=&quot;bevel&quot;/>&lt;Option type=&quot;QString&quot; name=&quot;line_color&quot; value=&quot;60,60,60,255,rgb:0.2352941,0.2352941,0.2352941,1&quot;/>&lt;Option type=&quot;QString&quot; name=&quot;line_style&quot; value=&quot;solid&quot;/>&lt;Option type=&quot;QString&quot; name=&quot;line_width&quot; value=&quot;0.3&quot;/>&lt;Option type=&quot;QString&quot; name=&quot;line_width_unit&quot; value=&quot;MM&quot;/>&lt;Option type=&quot;QString&quot; name=&quot;offset&quot; value=&quot;0&quot;/>&lt;Option type=&quot;QString&quot; name=&quot;offset_map_unit_scale&quot; value=&quot;3x:0,0,0,0,0,0&quot;/>&lt;Option type=&quot;QString&quot; name=&quot;offset_unit&quot; value=&quot;MM&quot;/>&lt;Option type=&quot;QString&quot; name=&quot;ring_filter&quot; value=&quot;0&quot;/>&lt;Option type=&quot;QString&quot; name=&quot;trim_distance_end&quot; value=&quot;0&quot;/>&lt;Option type=&quot;QString&quot; name=&quot;trim_distance_end_map_unit_scale&quot; value=&quot;3x:0,0,0,0,0,0&quot;/>&lt;Option type=&quot;QString&quot; name=&quot;trim_distance_end_unit&quot; value=&quot;MM&quot;/>&lt;Option type=&quot;QString&quot; name=&quot;trim_distance_start&quot; value=&quot;0&quot;/>&lt;Option type=&quot;QString&quot; name=&quot;trim_distance_start_map_unit_scale&quot; value=&quot;3x:0,0,0,0,0,0&quot;/>&lt;Option type=&quot;QString&quot; name=&quot;trim_distance_start_unit&quot; value=&quot;MM&quot;/>&lt;Option type=&quot;QString&quot; name=&quot;tweak_dash_pattern_on_corners&quot; value=&quot;0&quot;/>&lt;Option type=&quot;QString&quot; name=&quot;use_custom_dash&quot; value=&quot;0&quot;/>&lt;Option type=&quot;QString&quot; name=&quot;width_map_unit_scale&quot; value=&quot;3x:0,0,0,0,0,0&quot;/>&lt;/Option>&lt;data_defined_properties>&lt;Option type=&quot;Map&quot;>&lt;Option type=&quot;QString&quot; name=&quot;name&quot; value=&quot;&quot;/>&lt;Option name=&quot;properties&quot;/>&lt;Option type=&quot;QString&quot; name=&quot;type&quot; value=&quot;collection&quot;/>&lt;/Option>&lt;/data_defined_properties>&lt;/layer>&lt;/symbol>"/>
              <Option type="double" name="minLength" value="0"/>
              <Option type="QString" name="minLengthMapUnitScale" value="3x:0,0,0,0,0,0"/>
              <Option type="QString" name="minLengthUnit" value="MM"/>
              <Option type="double" name="offsetFromAnchor" value="0"/>
              <Option type="QString" name="offsetFromAnchorMapUnitScale" value="3x:0,0,0,0,0,0"/>
              <Option type="QString" name="offsetFromAnchorUnit" value="MM"/>
              <Option type="double" name="offsetFromLabel" value="0"/>
              <Option type="QString" name="offsetFromLabelMapUnitScale" value="3x:0,0,0,0,0,0"/>
              <Option type="QString" name="offsetFromLabelUnit" value="MM"/>
            </Option>
          </callout>
        </settings>
      </rule>
    </rules>
  </labeling>
  <blendMode>0</blendMode>
  <featureBlendMode>0</featureBlendMode>
  <layerOpacity>1</layerOpacity>
  <mapTip enabled="1">&lt;b>[% "nombre" %]&lt;/b>&lt;br>Código: [% "codigo" %]&lt;br>Área: [% round("area") %] m²</mapTip>
  <layerGeometryType>2</layerGeometryType>
</qgis>
